#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <atomic>
#include <memory>
#include <thread>
#include <vector>

#include "metal_log_state7_handler_lifetime.hpp"

static int test_multishot_cancel_gate() {
  constexpr int kIterations = 10000;
  auto gate = std::make_shared<PrismelLogHandlerGate>();
  std::atomic<int> admitted{0};
  std::vector<std::thread> workers;
  workers.reserve(4);
  for (int worker = 0; worker < 4; ++worker) {
    workers.emplace_back([gate, &admitted] {
      for (int iteration = 0; iteration < kIterations; ++iteration) {
        if (!gate->enter()) continue;
        admitted.fetch_add(1, std::memory_order_relaxed);
        gate->leave();
      }
    });
  }
  for (std::thread &worker : workers) worker.join();
  if (admitted.load(std::memory_order_relaxed) != 4 * kIterations) return 1;
  gate->cancel_and_wait();
  if (gate->active() || gate->enter()) return 2;

  PrismelLogHandlerGate in_flight;
  if (!in_flight.enter()) return 3;
  std::atomic<bool> cancelled{false};
  std::thread cancel([&] {
    in_flight.cancel_and_wait();
    cancelled.store(true, std::memory_order_release);
  });
  while (cancelled.load(std::memory_order_acquire)) return 4;
  in_flight.leave();
  cancel.join();
  if (!cancelled.load(std::memory_order_acquire) || in_flight.enter()) return 5;
  return 0;
}

int main() {
  @autoreleasepool {
    int gate_result = test_multishot_cancel_gate();
    if (gate_result != 0) return gate_result;

    if (@available(macOS 15.0, *)) {
      MTLLogStateDescriptor *descriptor = [MTLLogStateDescriptor new];
      descriptor.level = MTLLogLevelNotice;
      descriptor.bufferSize = 4096;
      MTLLogStateDescriptor *copy = [descriptor copy];
      descriptor.level = MTLLogLevelFault;
      descriptor.bufferSize = 8192;
      if (copy.level != MTLLogLevelNotice || copy.bufferSize != 4096) return 6;

      id<MTLDevice> device = MTLCreateSystemDefaultDevice();
      if (device == nil) return 77;
      NSError *error = nil;
      id<MTLLogState> state = [device newLogStateWithDescriptor:copy error:&error];
      if (state == nil) return error == nil ? 7 : 77;

      __weak NSObject *weak_capture = nil;
      @autoreleasepool {
        NSObject *capture = [NSObject new];
        weak_capture = capture;
        [state addLogHandler:^(NSString *subsystem, NSString *category,
                              MTLLogLevel level, NSString *message) {
          (void)subsystem;
          (void)category;
          (void)level;
          (void)message;
          (void)capture;
        }];
      }
      /* Metal must retain the registered block.  Safe cancellation cannot
         unregister it, so the block must retain only a small gate after the
         OCaml callback root has been released. */
      if (weak_capture == nil) return 8;
    }
  }
  return 0;
}
