#include "desktop_panel_host_registry.h"

DesktopPanelHostWindowRegistry& DesktopPanelHostRegistry() {
  static DesktopPanelHostWindowRegistry registry;
  return registry;
}
