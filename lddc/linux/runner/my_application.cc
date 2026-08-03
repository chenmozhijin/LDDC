#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

namespace {

constexpr int kPreferredMainWindowContentWidth = 1280;
constexpr int kPreferredMainWindowContentHeight = 720;

struct DesktopContentSize {
  int width;
  int height;
};

DesktopContentSize FitDesktopContentToWorkArea(int available_width,
                                               int available_height) {
  const double scale = std::min(
      {1.0,
       static_cast<double>(std::max(available_width, 1)) /
           kPreferredMainWindowContentWidth,
       static_cast<double>(std::max(available_height, 1)) /
           kPreferredMainWindowContentHeight});
  return DesktopContentSize{
      std::max(1, static_cast<int>(
                      std::floor(kPreferredMainWindowContentWidth * scale))),
      std::max(1, static_cast<int>(std::floor(
                      kPreferredMainWindowContentHeight * scale)))};
}

GdkRectangle ResolvePrimaryMonitorWorkArea() {
  GdkRectangle work_area = {0, 0, kPreferredMainWindowContentWidth,
                            kPreferredMainWindowContentHeight};
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr) {
    return work_area;
  }
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor != nullptr) {
    gdk_monitor_get_workarea(monitor, &work_area);
  }
  return work_area;
}

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* desktop_drag_drop_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Flutter 首帧完成后再显示窗口，避免 GTK 原生空窗口先闪一下。
static void first_frame_cb(MyApplication* self, FlView* view) {
  // 启动期的 size request 只用来保证首帧 Flutter 内容区精确命中
  // 统一尺寸。显示前立即解除，避免它变成用户无法缩小窗口的隐式最小值。
  gtk_widget_set_size_request(GTK_WIDGET(view), -1, -1);
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static FlValue* new_string_list(const std::vector<std::string>& values) {
  FlValue* list = fl_value_new_list();
  for (const std::string& value : values) {
    fl_value_append_take(list, fl_value_new_string(value.c_str()));
  }
  return list;
}

static FlValue* build_drag_payload(MyApplication* self, GtkWidget* widget,
                                   gdouble x, gdouble y,
                                   std::vector<std::string> files) {
  FlValue* payload = fl_value_new_map();
  fl_value_set_string_take(payload, "platform", fl_value_new_string("linux"));
  fl_value_set_string_take(payload, "x", fl_value_new_float(x));
  fl_value_set_string_take(payload, "y", fl_value_new_float(y));
  fl_value_set_string_take(payload, "coordinateSpace",
                           fl_value_new_string("logical"));
  std::vector<std::string> formats = {"text/uri-list"};
  fl_value_set_string_take(payload, "formats", new_string_list(formats));
  fl_value_set_string_take(payload, "files", new_string_list(files));
  fl_value_set_string_take(payload, "privateData", fl_value_new_map());
  return payload;
}

static void send_drag_event(MyApplication* self, const gchar* method,
                            GtkWidget* widget, gdouble x, gdouble y,
                            std::vector<std::string> files) {
  if (self->desktop_drag_drop_channel == nullptr) {
    return;
  }
  // GTK 侧只负责把 text/uri-list 里的本地文件路径交给 Dart；业务类型判断
  // 和页面命中测试统一留在 Flutter 层。
  g_autoptr(FlValue) payload = build_drag_payload(self, widget, x, y, files);
  fl_method_channel_invoke_method(self->desktop_drag_drop_channel, method,
                                  payload, nullptr, nullptr, nullptr);
}

static gboolean drag_motion_cb(GtkWidget* widget, GdkDragContext* context,
                               gint x, gint y, guint time, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  send_drag_event(self, "dragUpdate", widget, x, y, {});
  gdk_drag_status(context, GDK_ACTION_COPY, time);
  return TRUE;
}

static void drag_leave_cb(GtkWidget* widget, GdkDragContext* context,
                          guint time, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  send_drag_event(self, "dragLeave", widget, 0, 0, {});
}

static gboolean drag_drop_cb(GtkWidget* widget, GdkDragContext* context,
                             gint x, gint y, guint time, gpointer user_data) {
  GdkAtom target = gdk_atom_intern_static_string("text/uri-list");
  gtk_drag_get_data(widget, context, target, time);
  return TRUE;
}

static void drag_data_received_cb(GtkWidget* widget, GdkDragContext* context,
                                  gint x, gint y, GtkSelectionData* data,
                                  guint info, guint time,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  std::vector<std::string> files;
  gchar** uris = gtk_selection_data_get_uris(data);
  if (uris != nullptr) {
    for (gchar** cursor = uris; *cursor != nullptr; ++cursor) {
      g_autofree gchar* filename = g_filename_from_uri(*cursor, nullptr, nullptr);
      if (filename != nullptr) {
        files.emplace_back(filename);
      }
    }
    g_strfreev(uris);
  }
  send_drag_event(self, "performDrop", widget, x, y, files);
  gtk_drag_finish(context, !files.empty(), FALSE, time);
}

// 创建主 GTK 窗口并挂载 Flutter view。
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // GNOME/Wayland 使用 HeaderBar 更贴近平台习惯；非 GNOME 的 X11 窗口管理器保留传统标题栏，
  // 以免平铺窗口管理器或自定义装饰策略与 HeaderBar 冲突。
  gboolean use_header_bar = TRUE;
  gint header_bar_height = 0;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "LDDC");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
    gint minimum_height = 0;
    gtk_widget_get_preferred_height(GTK_WIDGET(header_bar), &minimum_height,
                                    &header_bar_height);
  } else {
    gtk_window_set_title(window, "LDDC");
  }

  const GdkRectangle work_area = ResolvePrimaryMonitorWorkArea();
  const DesktopContentSize initial_content = FitDesktopContentToWorkArea(
      work_area.width, work_area.height - header_bar_height);
  // GtkWindow 的自定义 HeaderBar 位于 Flutter view 之上。默认窗口高度
  // 显式加上其自然高度，避免 GNOME 下的 Flutter 内容区比 X11 少一条标题栏。
  gtk_window_set_default_size(window, initial_content.width,
                              initial_content.height + header_bar_height);
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(gdk_display_get_default())) {
    gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  }
#endif

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_set_size_request(GTK_WIDGET(view), initial_content.width,
                              initial_content.height);
  g_autoptr(FlStandardMethodCodec) drag_codec = fl_standard_method_codec_new();
  self->desktop_drag_drop_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "lddc/desktop_drag_drop", FL_METHOD_CODEC(drag_codec));

  GtkTargetEntry drag_targets[] = {
      {const_cast<gchar*>("text/uri-list"), 0, 0},
  };
  gtk_drag_dest_set(GTK_WIDGET(view), GTK_DEST_DEFAULT_ALL, drag_targets, 1,
                    GDK_ACTION_COPY);
  g_signal_connect(view, "drag-motion", G_CALLBACK(drag_motion_cb), self);
  g_signal_connect(view, "drag-leave", G_CALLBACK(drag_leave_cb), self);
  g_signal_connect(view, "drag-drop", G_CALLBACK(drag_drop_cb), self);
  g_signal_connect(view, "drag-data-received",
                   G_CALLBACK(drag_data_received_cb), self);
  GdkRGBA background_color;
  // Flutter view 默认黑底；这里显式固定，避免不同 GTK 主题改变启动阶段底色。
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // view realize 后才能收到 first-frame 信号，再显示窗口可减少启动闪烁。
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(
      [](FlPluginRegistry* registry) { fl_register_plugins(registry); });

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// 保留原始 Dart 参数，交给 Flutter 层解析窗口角色和桌面服务命令。
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// GApplication 生命周期入口，目前只转交父类。
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// GApplication 退出入口，目前只转交父类。
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// 释放从命令行复制出来的 Dart 参数。
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->desktop_drag_drop_channel);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // prgname 使用 application id，桌面环境才能把运行中进程与 .desktop 文件稳定关联。
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
