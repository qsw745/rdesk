#include "wake_adapter_bridge.h"
#include <ws2ipdef.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <flutter/standard_method_codec.h>
#include <chrono>
#include <cstdio>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
std::string Utf8(const wchar_t* text) {
  if (!text || !*text) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, output.data(), size, nullptr, nullptr);
  output.pop_back();
  return output;
}
Value Error(const char* api, ULONG code) {
  return Value(Map{{Value("api"), Value(api)}, {Value("code"), Value(static_cast<int64_t>(code))}});
}
Value Enumerate(bool& failed) {
  ULONG size = 16384;
  std::vector<unsigned char> buffer(size);
  ULONG code = ERROR_BUFFER_OVERFLOW;
  for (int attempt = 0; attempt < 3 && code == ERROR_BUFFER_OVERFLOW; ++attempt) {
    buffer.resize(size);
    code = GetAdaptersAddresses(AF_UNSPEC,
      GAA_FLAG_INCLUDE_ALL_INTERFACES | GAA_FLAG_SKIP_ANYCAST |
      GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, nullptr,
      reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
  }
  List adapters;
  int errors = 0;
  int seen = 0;
  if (code != NO_ERROR && code != ERROR_NO_DATA) {
    failed = true;
    return Error("GetAdaptersAddresses", code);
  }
  if (code == NO_ERROR) {
    for (auto* nic = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); nic; nic = nic->Next) {
      ++seen;
      MIB_IF_ROW2 row{};
      row.InterfaceLuid = nic->Luid;
      code = GetIfEntry2(&row);
      if (code != NO_ERROR) { ++errors; continue; }
      if (row.PhysicalAddressLength != 6) continue;
      char mac[18];
      snprintf(mac, sizeof(mac), "%02X:%02X:%02X:%02X:%02X:%02X",
        row.PhysicalAddress[0], row.PhysicalAddress[1], row.PhysicalAddress[2],
        row.PhysicalAddress[3], row.PhysicalAddress[4], row.PhysicalAddress[5]);
      adapters.emplace_back(Map{
        {Value("id"), Value(nic->AdapterName ? nic->AdapterName : "")},
        {Value("name"), Value(Utf8(nic->FriendlyName))},
        {Value("mac"), Value(mac)},
        {Value("if_type"), Value(static_cast<int>(row.Type))},
        {Value("hardware"), Value(row.InterfaceAndOperStatusFlags.HardwareInterface != 0)},
        {Value("connected"), Value(row.OperStatus == IfOperStatusUp)}});
    }
  }
  if (seen > 0 && errors == seen) { failed = true; return Error("GetIfEntry2", code); }
  return Value(Map{{Value("schema"), Value(1)}, {Value("source"), Value("ip_helper")},
    {Value("query_errors"), Value(errors)}, {Value("adapters"), Value(adapters)}});
}
}
WakeAdapterBridge::WakeAdapterBridge(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
    messenger, "com.qsw.rdesk/windows_wake", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<Value>& call,
      std::unique_ptr<flutter::MethodResult<Value>> result) {
    if (call.method_name() != "listAdapters") { result->NotImplemented(); return; }
    if (pending_) { result->Error("adapter_busy", "检测正在进行"); return; }
    pending_ = std::move(result);
    worker_ = std::thread([this]() {
      bool failed = false;
      const auto start = std::chrono::steady_clock::now();
      Value payload;
      try { payload = Enumerate(failed); }
      catch (...) { failed = true; payload = Error("GetAdaptersAddresses", ERROR_NOT_ENOUGH_MEMORY); }
      auto& data = std::get<Map>(payload);
      data[Value("elapsed_ms")] = Value(static_cast<int64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count()));
      { std::lock_guard<std::mutex> lock(mutex_); payload_ = std::move(payload); failed_ = failed; }
      PostMessage(window_, kResultMessage, 0, 0);
    });
  });
}
WakeAdapterBridge::~WakeAdapterBridge() {
  channel_->SetMethodCallHandler(nullptr);
  if (worker_.joinable()) worker_.join();
  pending_.reset();
}
void WakeAdapterBridge::Complete() {
  if (!pending_) return;
  if (worker_.joinable()) worker_.join();
  auto result = std::move(pending_);
  std::lock_guard<std::mutex> lock(mutex_);
  if (failed_) result->Error("adapter_query", "Windows 网卡查询失败", payload_);
  else result->Success(payload_);
}
