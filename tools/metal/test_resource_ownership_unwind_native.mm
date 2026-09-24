#include <atomic>
#include <cassert>
#include <cstddef>
#include <iostream>

struct Native_handle_audit {
  std::atomic<std::size_t> &live;
  bool owned = false;
  explicit Native_handle_audit(std::atomic<std::size_t> &counter) : live(counter) {}
  void allocate() { assert(!owned); owned = true; ++live; }
  void unwind() { if (owned) { owned = false; --live; } }
  ~Native_handle_audit() { unwind(); }
};

int main() {
  std::atomic<std::size_t> live{0};
  for (std::size_t i = 0; i < 10'000; ++i) {
    Native_handle_audit result(live), descriptor(live), completion(live);
    descriptor.allocate();
    if (i % 3) {
      result.allocate();
      if (i % 5 == 0) result.unwind(); // safe attachment failure
    }
    descriptor.unwind();               // NSError/exception or success
    completion.allocate();
    if (i % 7 == 0) completion.unwind(); // command encoding rejection
  }
  assert(live == 0);
  std::cout << "resource native unwind: 10k nullable/descriptor/completion paths, zero live tokens\n";
}
