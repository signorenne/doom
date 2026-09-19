#include <doctest/doctest.h>

#include <cstdint>
#include <limits>

#include <{{PROJECT}}/counter.hpp>

namespace {
using counter = {{PROJECT}}::counter<std::uint8_t>;
}  // namespace

TEST_CASE("a fresh counter is zero") {
  static_assert(counter{}.value() == 0);
}

TEST_CASE("add returns the new value") {
  auto c{counter{}};
  auto const first{c.add(10)};
  REQUIRE(first.has_value());
  CHECK(*first == 10);
  CHECK(c.value() == 10);
}

TEST_CASE("add reports overflow and leaves the count alone") {
  auto c{counter{}};
  REQUIRE(c.add(std::numeric_limits<std::uint8_t>::max()).has_value());

  auto const overflowed{c.add(1)};
  REQUIRE_FALSE(overflowed.has_value());
  CHECK(overflowed.error() == {{PROJECT}}::counter_error::overflow);
  CHECK(c.value() == std::numeric_limits<std::uint8_t>::max());
}

TEST_CASE("subtract reports underflow and leaves the count alone") {
  auto c{counter{}};
  REQUIRE(c.add(5).has_value());

  auto const underflowed{c.subtract(6)};
  REQUIRE_FALSE(underflowed.has_value());
  CHECK(underflowed.error() == {{PROJECT}}::counter_error::underflow);
  CHECK(c.value() == 5);

  auto const down{c.subtract(5)};
  REQUIRE(down.has_value());
  CHECK(*down == 0);
}

TEST_CASE("reset returns to zero") {
  auto c{counter{}};
  REQUIRE(c.add(7).has_value());
  c.reset();
  CHECK(c.value() == 0);
}

TEST_CASE("counters compare by their value") {
  auto const two{[]() -> counter {
    auto c{counter{}};
    [[maybe_unused]] auto const ignored{c.add(2)};
    return c;
  }()};

  CHECK(two == two);
  CHECK(counter{} < two);
}
