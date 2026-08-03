#include "embedded_panel_channel_plugin.h"

#include <flutter/encodable_value.h>

#include <algorithm>

namespace {

enum class EmbeddedPanelRegistrationOutcome {
  kAdded,
  kAlreadyRegistered,
  kLimitReached,
};

class EmbeddedPanelChannelRegistry {
 public:
  static EmbeddedPanelChannelRegistry& GetInstance() {
    static EmbeddedPanelChannelRegistry instance;
    return instance;
  }

  EmbeddedPanelRegistrationOutcome Register(
      const std::string& channel,
      EmbeddedPanelChannelPlugin* plugin) {
    std::lock_guard<std::mutex> lock(mutex_);
    return RegisterBidirectional(channel, plugin);
  }

  void Unregister(const std::string& channel,
                  EmbeddedPanelChannelPlugin* plugin) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto bi_it = bidirectional_channels_.find(channel);
    if (bi_it != bidirectional_channels_.end()) {
      bi_it->second.erase(plugin);
      if (bi_it->second.empty()) {
        bidirectional_channels_.erase(bi_it);
      }
    }
  }

  EmbeddedPanelChannelPlugin* GetTarget(const std::string& channel,
                                        EmbeddedPanelChannelPlugin* from) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto bi_it = bidirectional_channels_.find(channel);
    if (bi_it == bidirectional_channels_.end()) {
      return nullptr;
    }
    if (bi_it->second.find(from) == bi_it->second.end()) {
      return nullptr;
    }
    for (auto* plugin : bi_it->second) {
      if (plugin != from) {
        return plugin;
      }
    }
    return nullptr;
  }

 private:
  EmbeddedPanelRegistrationOutcome RegisterBidirectional(
      const std::string& channel,
      EmbeddedPanelChannelPlugin* plugin) {
    auto& plugins = bidirectional_channels_[channel];
    if (plugins.find(plugin) != plugins.end()) {
      return EmbeddedPanelRegistrationOutcome::kAlreadyRegistered;
    }
    if (plugins.size() >= 2) {
      return EmbeddedPanelRegistrationOutcome::kLimitReached;
    }
    plugins.insert(plugin);
    return EmbeddedPanelRegistrationOutcome::kAdded;
  }

  std::mutex mutex_;
  std::map<std::string, std::set<EmbeddedPanelChannelPlugin*>>
      bidirectional_channels_;
};

}  // namespace

void EmbeddedPanelChannelPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<EmbeddedPanelChannelPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

EmbeddedPanelChannelPlugin::EmbeddedPanelChannelPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<>>(
      registrar_->messenger(), "lddc/embedded_panel_channels",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<flutter::MethodResult<>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

EmbeddedPanelChannelPlugin::~EmbeddedPanelChannelPlugin() {
  for (const auto& channel : registered_channels_) {
    EmbeddedPanelChannelRegistry::GetInstance().Unregister(channel, this);
  }
}

void EmbeddedPanelChannelPlugin::InvokeMethod(
    const std::string& channel,
    const flutter::EncodableValue& arguments,
    std::unique_ptr<flutter::MethodResult<>> result) {
  if (std::find(registered_channels_.begin(), registered_channels_.end(),
                channel) == registered_channels_.end()) {
    result->Error("CHANNEL_NOT_FOUND",
                  "channel " + channel + " not found in this engine");
    return;
  }
  channel_->InvokeMethod(
      "methodCall", std::make_unique<flutter::EncodableValue>(arguments),
      std::move(result));
}

void EmbeddedPanelChannelPlugin::HandleMethodCall(
    const flutter::MethodCall<>& call,
    std::unique_ptr<flutter::MethodResult<>> result) {
  const std::string& method = call.method_name();

  if (method == "registerMethodHandler") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("INVALID_ARGUMENTS", "arguments must be a map");
      return;
    }
    auto channel_it = args->find(flutter::EncodableValue("channel"));
    if (channel_it == args->end()) {
      result->Error("INVALID_ARGUMENTS", "channel is required");
      return;
    }
    const auto* channel = std::get_if<std::string>(&channel_it->second);
    if (channel == nullptr) {
      result->Error("INVALID_ARGUMENTS", "channel must be a string");
      return;
    }
    switch (EmbeddedPanelChannelRegistry::GetInstance().Register(*channel,
                                                                this)) {
      case EmbeddedPanelRegistrationOutcome::kAdded:
        registered_channels_.push_back(*channel);
        result->Success();
        return;
      case EmbeddedPanelRegistrationOutcome::kAlreadyRegistered:
        result->Success();
        return;
      case EmbeddedPanelRegistrationOutcome::kLimitReached:
        result->Error("CHANNEL_LIMIT_REACHED",
                      "channel " + *channel +
                          " already reached the registration limit");
        return;
    }
  }

  if (method == "unregisterMethodHandler") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("INVALID_ARGUMENTS", "arguments must be a map");
      return;
    }
    auto channel_it = args->find(flutter::EncodableValue("channel"));
    if (channel_it == args->end()) {
      result->Error("INVALID_ARGUMENTS", "channel is required");
      return;
    }
    const auto* channel = std::get_if<std::string>(&channel_it->second);
    if (channel == nullptr) {
      result->Error("INVALID_ARGUMENTS", "channel must be a string");
      return;
    }
    EmbeddedPanelChannelRegistry::GetInstance().Unregister(*channel, this);
    auto it =
        std::find(registered_channels_.begin(), registered_channels_.end(),
                  *channel);
    if (it != registered_channels_.end()) {
      registered_channels_.erase(it);
    }
    result->Success();
    return;
  }

  if (method == "invokeMethod") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("INVALID_ARGUMENTS", "arguments must be a map");
      return;
    }
    auto channel_it = args->find(flutter::EncodableValue("channel"));
    if (channel_it == args->end()) {
      result->Error("INVALID_ARGUMENTS", "channel is required");
      return;
    }
    const auto* channel = std::get_if<std::string>(&channel_it->second);
    if (channel == nullptr) {
      result->Error("INVALID_ARGUMENTS", "channel must be a string");
      return;
    }
    EmbeddedPanelChannelPlugin* target =
        EmbeddedPanelChannelRegistry::GetInstance().GetTarget(*channel, this);
    if (target == nullptr) {
      result->Error("CHANNEL_UNREGISTERED",
                    "channel " + *channel + " not accessible");
      return;
    }
    target->InvokeMethod(*channel, *call.arguments(), std::move(result));
    return;
  }

  result->NotImplemented();
}
