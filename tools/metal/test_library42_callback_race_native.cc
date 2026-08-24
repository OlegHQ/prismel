#include <atomic>
#include <cassert>
#include <memory>
#include <thread>

namespace {
std::atomic<int> live_roots{0};
std::atomic<int> live_tokens{0};
std::atomic<int> callbacks{0};

struct Root {
  Root() { ++live_roots; }
  ~Root() { --live_roots; }
};

struct State {
  std::atomic<int> phase{0}; // pending, fired, cancelled
  std::unique_ptr<Root> root{std::make_unique<Root>()};
};

struct Token {
  explicit Token(std::shared_ptr<State> state) : state(std::move(state)) {
    ++live_tokens;
  }
  ~Token() { --live_tokens; }
  std::shared_ptr<State> state;
};

void fire(const std::shared_ptr<State>& state) {
  int pending = 0;
  if (state->phase.compare_exchange_strong(pending, 1)) {
    ++callbacks;
    state->root.reset();
  }
}

void cancel(Token& token) {
  int pending = 0;
  if (token.state->phase.compare_exchange_strong(pending, 2))
    token.state->root.reset();
}
} // namespace

int main() {
  constexpr int registrations = 10'000;
  for (int index = 0; index < registrations; ++index) {
    auto state = std::make_shared<State>();
    Token token(state);
    const int before = callbacks.load();
    std::thread firing([state] { fire(state); });
    std::thread cancelling([&token] { cancel(token); });
    firing.join();
    cancelling.join();
    assert(state->phase.load() != 0);
    assert(callbacks.load() - before == (state->phase.load() == 1 ? 1 : 0));
    assert(!state->root);
  }
  assert(live_roots.load() == 0);
  assert(live_tokens.load() == 0);
  return 0;
}
