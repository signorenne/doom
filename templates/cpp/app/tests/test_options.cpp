#include <doctest/doctest.h>

#include <array>
#include <span>

#include <{{PROJECT}}/options.hpp>

namespace opts = {{PROJECT}};

TEST_CASE("an empty command line gives the defaults") {
  auto const parsed{opts::parse({})};
  REQUIRE(parsed.has_value());
  CHECK(parsed->name == "world");
  CHECK_FALSE(parsed->verbose);
}

TEST_CASE("--name takes the next argument") {
  auto const arguments{std::array<char const*, 2>{"--name", "ada"}};
  auto const parsed{opts::parse(arguments)};
  REQUIRE(parsed.has_value());
  CHECK(parsed->name == "ada");
}

TEST_CASE("--verbose is a flag") {
  auto const arguments{std::array<char const*, 1>{"--verbose"}};
  auto const parsed{opts::parse(arguments)};
  REQUIRE(parsed.has_value());
  CHECK(parsed->verbose);
}

TEST_CASE("a flag without its value is an error") {
  auto const arguments{std::array<char const*, 1>{"--name"}};
  auto const parsed{opts::parse(arguments)};
  REQUIRE_FALSE(parsed.has_value());
  CHECK(parsed.error() == opts::option_error::missing_value);
}

TEST_CASE("an unknown flag is an error") {
  auto const arguments{std::array<char const*, 1>{"--colour"}};
  auto const parsed{opts::parse(arguments)};
  REQUIRE_FALSE(parsed.has_value());
  CHECK(parsed.error() == opts::option_error::unknown_flag);
}
