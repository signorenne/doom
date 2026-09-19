/**
 * @file
 * @brief Counts up to the limit of the underlying type and reports the
 *        overflow rather than wrapping.
 */

#include <cstdint>
#include <print>

#include <{{PROJECT}}/counter.hpp>

auto main() -> int {
  auto c{{{PROJECT}}::counter<std::uint8_t>{}};

  for (auto step{0}; step < 3; ++step) {
    auto const result{c.add(100)};
    if (result.has_value()) {
      std::println("count is {}", *result);
    } else {
      std::println("stopped at {}: {}", c.value(), {{PROJECT}}::to_string(result.error()));
    }
  }

  return 0;
}
