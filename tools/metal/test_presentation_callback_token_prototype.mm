#include "presentation_callback_token_prototype.mm"

#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <thread>

using namespace prismel::metal::presentation_callback_prototype;

struct Audit_runtime final : Runtime {
  std::atomic<std::size_t> live_roots{0};
  std::atomic<std::size_t> callbacks{0};
  std::atomic<std::size_t> ordering_failures{0};
  static thread_local bool registered;
  static thread_local bool held;

  bool register_foreign_thread() override {
    const bool newly_registered = !registered;
    registered = true;
    return newly_registered;
  }
  void acquire() override {
    if (!registered || held) ordering_failures.fetch_add(1);
    held = true;
  }
  void invoke(void *) override {
    if (!registered || !held) ordering_failures.fetch_add(1);
    callbacks.fetch_add(1);
  }
  void remove_root(void *) override {
    // cancel_runtime_held is invoked by the main test thread, modelling an
    // OCaml primitive which already owns the runtime.
    live_roots.fetch_sub(1);
  }
  void release() override {
    if (!held) ordering_failures.fetch_add(1);
    held = false;
  }
  void unregister_foreign_thread() override {
    if (held || !registered) ordering_failures.fetch_add(1);
    registered = false;
  }
};

thread_local bool Audit_runtime::registered = false;
thread_local bool Audit_runtime::held = false;

int main() {
  constexpr std::size_t registrations = 10'000;
  Audit_runtime runtime;
  std::atomic<std::size_t> live_tokens{0};
  std::atomic<std::size_t> fire_wins{0};
  std::atomic<std::size_t> cancel_wins{0};

  for (std::uintptr_t index = 1; index <= registrations; ++index) {
    runtime.live_roots.fetch_add(1);
    auto token = make_token(runtime, reinterpret_cast<void *>(index), live_tokens);
    auto native_block_capture = token;
    std::atomic<bool> start{false};
    std::thread metal_thread([native_block_capture, &start, &fire_wins] {
      while (!start.load(std::memory_order_acquire)) std::this_thread::yield();
      if (native_block_capture->fire()) fire_wins.fetch_add(1);
    });
    start.store(true, std::memory_order_release);
    if (token->cancel_runtime_held()) cancel_wins.fetch_add(1);
    metal_thread.join();
    native_block_capture.reset();
    token.reset();
  }

  assert(fire_wins + cancel_wins == registrations);
  assert(runtime.callbacks == fire_wins);
  assert(runtime.live_roots == 0);
  assert(live_tokens == 0);
  assert(runtime.ordering_failures == 0);
  std::cout << "presentation callback token: " << registrations
            << " fire/cancel races, zero roots/tokens, runtime ordering green\n";
}
