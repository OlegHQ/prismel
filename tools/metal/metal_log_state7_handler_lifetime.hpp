#pragma once

#include <condition_variable>
#include <cstddef>
#include <mutex>

/* MTLLogState has no removeLogHandler: selector.  The native block therefore
   retains this state for as long as Metal retains the handler, while cancel()
   only closes the client callback gate.  A delivery admitted before cancel
   may finish; later deliveries are rejected. */
class PrismelLogHandlerGate {
 public:
  bool enter() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!active_) return false;
    ++in_flight_;
    return true;
  }

  void leave() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (in_flight_ == 0) return;
    --in_flight_;
    if (in_flight_ == 0) idle_.notify_all();
  }

  void cancel_and_wait() {
    std::unique_lock<std::mutex> lock(mutex_);
    active_ = false;
    idle_.wait(lock, [this] { return in_flight_ == 0; });
  }

  bool active() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return active_;
  }

 private:
  mutable std::mutex mutex_;
  std::condition_variable idle_;
  bool active_ = true;
  std::size_t in_flight_ = 0;
};
