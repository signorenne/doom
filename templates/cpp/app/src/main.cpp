/**
 * @file
 * @brief Entry point: parses the command line and greets.
 */

#include <cstdlib>
#include <print>
#include <span>

#include <{{PROJECT}}/options.hpp>

auto main(int argc, char** const argv) -> int {
  auto const arguments{std::span{argv, static_cast<std::size_t>(argc)}.subspan(1)};
  auto const parsed{{{PROJECT}}::parse(arguments)};

  if (!parsed.has_value()) {
    std::println(stderr, "{{PROJECT}}: {}", {{PROJECT}}::to_string(parsed.error()));
    std::println(stderr, "usage: {{PROJECT}} [--name NAME] [--verbose]");
    return EXIT_FAILURE;
  }

  if (parsed->verbose) {
    std::println("greeting {}", parsed->name);
  }
  std::println("hello, {}", parsed->name);

  return EXIT_SUCCESS;
}
