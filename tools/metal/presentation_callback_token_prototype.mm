#include <atomic>
#include <cstddef>
#include <memory>

namespace prismel::metal::presentation_callback_prototype {

// Runtime operations are injected so the token algorithm can be stress-tested
// without embedding an OCaml runtime.  The production adapter maps these calls
// directly to caml_c_thread_register/acquire_runtime_system/callback_exn/
// remove_generational_global_root/release_runtime_system/c_thread_unregister.
struct Runtime {
  virtual bool register_foreign_thread() = 0;
  virtual void acquire() = 0;
  virtual void invoke(void *root) = 0;
  virtual void remove_root(void *root) = 0;
  virtual void release() = 0;
  virtual void unregister_foreign_thread() = 0;
  virtual ~Runtime() = default;
};

class Token final {
 public:
  Token(Runtime &runtime, void *root, std::atomic<std::size_t> &live_tokens)
      : runtime_(runtime), root_(root), live_tokens_(live_tokens) {
    live_tokens_.fetch_add(1, std::memory_order_relaxed);
  }

  Token(const Token &) = delete;
  Token &operator=(const Token &) = delete;

  // Called by a Metal scheduled/completed handler on an arbitrary native
  // thread.  Exactly one of fire/cancel may claim the root.
  bool fire() {
    if (!claim()) return false;
    const bool registered = runtime_.register_foreign_thread();
    runtime_.acquire();
    runtime_.invoke(root_); // production uses caml_callback_exn
    runtime_.remove_root(root_);
    runtime_.release();
    if (registered) runtime_.unregister_foreign_thread();
    return true;
  }

  // Called only by an OCaml primitive/finalizer while it already owns the
  // runtime.  Acquiring it recursively here would deadlock.
  bool cancel_runtime_held() {
    if (!claim()) return false;
    runtime_.remove_root(root_);
    return true;
  }

  ~Token() { live_tokens_.fetch_sub(1, std::memory_order_relaxed); }

 private:
  bool claim() {
    bool expected = false;
    return terminal_.compare_exchange_strong(expected, true,
                                             std::memory_order_acq_rel,
                                             std::memory_order_acquire);
  }

  Runtime &runtime_;
  void *root_;
  std::atomic<std::size_t> &live_tokens_;
  std::atomic<bool> terminal_{false};
};

using Shared_token = std::shared_ptr<Token>;

Shared_token make_token(Runtime &runtime, void *root,
                        std::atomic<std::size_t> &live_tokens) {
  return std::make_shared<Token>(runtime, root, live_tokens);
}

} // namespace prismel::metal::presentation_callback_prototype
