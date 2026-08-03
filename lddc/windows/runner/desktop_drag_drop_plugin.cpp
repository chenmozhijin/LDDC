#include "desktop_drag_drop_plugin.h"

#include <flutter/encodable_value.h>
#include <ole2.h>
#include <shellapi.h>

#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include "utils.h"

namespace {

constexpr char kChannelName[] = "lddc/desktop_drag_drop";
constexpr size_t kPrivateDataMaxBytes = 1024 * 1024;
constexpr wchar_t kFoobarRawFormat[] = L"foobar2000_playable_location_format";
constexpr wchar_t kAimpRawFormat[] = L"ACL.FileURIs";
constexpr wchar_t kAimpTextFormat[] = L"text/aimp-uri-list";

std::string ClipboardFormatName(CLIPFORMAT format) {
  switch (format) {
    case CF_HDROP:
      return "CF_HDROP";
    case CF_UNICODETEXT:
      return "CF_UNICODETEXT";
    case CF_TEXT:
      return "CF_TEXT";
    default:
      break;
  }
  wchar_t name[256] = {};
  const int copied = ::GetClipboardFormatNameW(format, name, 256);
  if (copied <= 0) {
    return std::string();
  }
  return Utf8FromUtf16(name);
}

std::vector<std::string> EnumerateFormats(IDataObject* data_object) {
  std::vector<std::string> formats;
  if (data_object == nullptr) {
    return formats;
  }
  IEnumFORMATETC* enumerator = nullptr;
  if (FAILED(data_object->EnumFormatEtc(DATADIR_GET, &enumerator)) ||
      enumerator == nullptr) {
    return formats;
  }
  FORMATETC item = {};
  while (enumerator->Next(1, &item, nullptr) == S_OK) {
    std::string name = ClipboardFormatName(item.cfFormat);
    if (!name.empty() &&
        std::find(formats.begin(), formats.end(), name) == formats.end()) {
      formats.push_back(std::move(name));
    }
    if (item.ptd != nullptr) {
      ::CoTaskMemFree(item.ptd);
    }
  }
  enumerator->Release();
  return formats;
}

bool ReadHGlobalBytes(IDataObject* data_object, CLIPFORMAT format,
                      std::vector<uint8_t>* bytes) {
  if (data_object == nullptr || bytes == nullptr) {
    return false;
  }
  FORMATETC format_request = {};
  format_request.cfFormat = format;
  format_request.dwAspect = DVASPECT_CONTENT;
  format_request.lindex = -1;
  format_request.tymed = TYMED_HGLOBAL;
  STGMEDIUM medium = {};
  if (FAILED(data_object->GetData(&format_request, &medium)) ||
      medium.tymed != TYMED_HGLOBAL || medium.hGlobal == nullptr) {
    return false;
  }
  const SIZE_T size = ::GlobalSize(medium.hGlobal);
  bool ok = false;
  if (size > 0 && size <= kPrivateDataMaxBytes) {
    const void* locked = ::GlobalLock(medium.hGlobal);
    if (locked != nullptr) {
      const auto* first = static_cast<const uint8_t*>(locked);
      bytes->assign(first, first + size);
      ::GlobalUnlock(medium.hGlobal);
      ok = true;
    }
  }
  ::ReleaseStgMedium(&medium);
  return ok;
}

std::string ReadUnicodeText(IDataObject* data_object) {
  std::vector<uint8_t> bytes;
  if (!ReadHGlobalBytes(data_object, CF_UNICODETEXT, &bytes) ||
      bytes.size() < sizeof(wchar_t)) {
    return std::string();
  }
  return Utf8FromUtf16(reinterpret_cast<const wchar_t*>(bytes.data()));
}

std::vector<std::string> ReadDroppedFiles(IDataObject* data_object) {
  std::vector<std::string> files;
  FORMATETC format_request = {};
  format_request.cfFormat = CF_HDROP;
  format_request.dwAspect = DVASPECT_CONTENT;
  format_request.lindex = -1;
  format_request.tymed = TYMED_HGLOBAL;
  STGMEDIUM medium = {};
  if (FAILED(data_object->GetData(&format_request, &medium)) ||
      medium.tymed != TYMED_HGLOBAL || medium.hGlobal == nullptr) {
    return files;
  }
  HDROP drop = static_cast<HDROP>(medium.hGlobal);
  const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT index = 0; index < count; ++index) {
    const UINT length = ::DragQueryFileW(drop, index, nullptr, 0);
    if (length == 0) {
      continue;
    }
    std::wstring path(length + 1, L'\0');
    if (::DragQueryFileW(drop, index, path.data(), length + 1) == 0) {
      continue;
    }
    path.resize(length);
    files.push_back(Utf8FromUtf16(path.c_str()));
  }
  ::ReleaseStgMedium(&medium);
  return files;
}

flutter::EncodableList ToEncodableList(const std::vector<std::string>& values) {
  flutter::EncodableList result;
  result.reserve(values.size());
  for (const std::string& value : values) {
    result.emplace_back(value);
  }
  return result;
}

flutter::EncodableMap ReadPrivateData(IDataObject* data_object) {
  flutter::EncodableMap result;
  const std::vector<std::pair<std::wstring, std::string>> formats = {
      {kFoobarRawFormat, "foobar2000_playable_location_format"},
      {kAimpRawFormat, "ACL.FileURIs"},
      {kAimpTextFormat, "text/aimp-uri-list"},
  };
  for (const auto& entry : formats) {
    const CLIPFORMAT format = static_cast<CLIPFORMAT>(
        ::RegisterClipboardFormatW(entry.first.c_str()));
    if (format == 0) {
      continue;
    }
    std::vector<uint8_t> bytes;
    if (ReadHGlobalBytes(data_object, format, &bytes)) {
      result[flutter::EncodableValue(entry.second)] =
          flutter::EncodableValue(std::move(bytes));
    }
  }
  return result;
}

flutter::EncodableMap BuildPayload(HWND hwnd, IDataObject* data_object,
                                   POINTL point, bool include_data) {
  POINT client_point = {point.x, point.y};
  ::ScreenToClient(hwnd, &client_point);
  const UINT dpi = ::GetDpiForWindow(hwnd);
  const double scale = dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;

  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("platform")] =
      flutter::EncodableValue("windows");
  payload[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(client_point.x) / scale);
  payload[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(client_point.y) / scale);
  payload[flutter::EncodableValue("coordinateSpace")] =
      flutter::EncodableValue("logical");
  payload[flutter::EncodableValue("formats")] =
      flutter::EncodableValue(ToEncodableList(EnumerateFormats(data_object)));

  if (include_data) {
    payload[flutter::EncodableValue("files")] =
        flutter::EncodableValue(ToEncodableList(ReadDroppedFiles(data_object)));
    payload[flutter::EncodableValue("privateData")] =
        flutter::EncodableValue(ReadPrivateData(data_object));
    const std::string text = ReadUnicodeText(data_object);
    if (!text.empty()) {
      payload[flutter::EncodableValue("text")] = flutter::EncodableValue(text);
    }
  } else {
    payload[flutter::EncodableValue("files")] =
        flutter::EncodableValue(flutter::EncodableList());
    payload[flutter::EncodableValue("privateData")] =
        flutter::EncodableValue(flutter::EncodableMap());
  }
  return payload;
}

class DesktopDropTarget : public IDropTarget {
 public:
  explicit DesktopDropTarget(DesktopDragDropPlugin* plugin)
      : plugin_(plugin) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,
                                           void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }
    if (iid == IID_IUnknown || iid == IID_IDropTarget) {
      *object = static_cast<IDropTarget*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(::InterlockedIncrement(&ref_count_));
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count =
        static_cast<ULONG>(::InterlockedDecrement(&ref_count_));
    if (count == 0) {
      delete this;
    }
    return count;
  }

  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data_object,
                                      DWORD key_state, POINTL point,
                                      DWORD* effect) override {
    if (effect != nullptr) {
      *effect = DROPEFFECT_COPY;
    }
    if (plugin_ != nullptr) {
      plugin_->SendDragEvent("dragEnter", data_object, point, false);
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragOver(DWORD key_state, POINTL point,
                                     DWORD* effect) override {
    if (effect != nullptr) {
      *effect = DROPEFFECT_COPY;
    }
    if (plugin_ != nullptr) {
      plugin_->SendDragEvent("dragUpdate", nullptr, point, false);
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragLeave() override {
    if (plugin_ != nullptr) {
      POINTL point = {};
      plugin_->SendDragEvent("dragLeave", nullptr, point, false);
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data_object, DWORD key_state,
                                 POINTL point, DWORD* effect) override {
    if (effect != nullptr) {
      *effect = DROPEFFECT_COPY;
    }
    if (plugin_ != nullptr) {
      plugin_->SendDragEvent("performDrop", data_object, point, true);
    }
    return S_OK;
  }

 private:
  ~DesktopDropTarget() = default;

  LONG ref_count_ = 1;
  DesktopDragDropPlugin* plugin_ = nullptr;
};

}  // namespace

void DesktopDragDropPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  if (registrar == nullptr || registrar->GetView() == nullptr) {
    return;
  }
  HWND hwnd = registrar->GetView()->GetNativeWindow();
  if (hwnd == nullptr) {
    return;
  }
  auto plugin = std::make_unique<DesktopDragDropPlugin>(registrar, hwnd);
  registrar->AddPlugin(std::move(plugin));
}

DesktopDragDropPlugin::DesktopDragDropPlugin(
    flutter::PluginRegistrarWindows* registrar, HWND hwnd)
    : hwnd_(hwnd) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  ole_result_ = ::OleInitialize(nullptr);
  if (FAILED(ole_result_)) {
    return;
  }
  drop_target_ = new DesktopDropTarget(this);
  const HRESULT register_result = ::RegisterDragDrop(hwnd_, drop_target_);
  if (FAILED(register_result)) {
    drop_target_->Release();
    drop_target_ = nullptr;
  }
}

DesktopDragDropPlugin::~DesktopDragDropPlugin() {
  if (drop_target_ != nullptr) {
    ::RevokeDragDrop(hwnd_);
    drop_target_->Release();
    drop_target_ = nullptr;
  }
  if (SUCCEEDED(ole_result_)) {
    ::OleUninitialize();
  }
}

void DesktopDragDropPlugin::SendDragEvent(const char* method,
                                          IDataObject* data_object,
                                          POINTL point, bool include_data) {
  if (channel_ == nullptr || method == nullptr) {
    return;
  }
  channel_->InvokeMethod(
      method,
      std::make_unique<flutter::EncodableValue>(
          BuildPayload(hwnd_, data_object, point, include_data)));
}
