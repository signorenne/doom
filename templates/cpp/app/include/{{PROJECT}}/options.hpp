#pragma once

/**
 * @file
 * @brief Command line options for {{PROJECT}}.
 */

#include <cstdint>
#include <expected>
#include <span>
#include <string_view>

namespace {{PROJECT}} {

/// @brief Why parsing the command line failed.
enum class option_error : std::uint8_t {
  unknown_flag,   ///< A flag the program does not define.
  missing_value,  ///< A flag that takes a value was given none.
};

/**
 * @brief Turns an \c option_error into a readable name.
 *
 * @param error The error to name.
 *
 * @return A static string naming the error.
 *
 * @pre None.
 * @post None.
 */
[[nodiscard]] constexpr auto to_string(option_error const error) noexcept -> char const* {
  switch (error) {
    case option_error::unknown_flag:
      return "unknown flag";
    case option_error::missing_value:
      return "missing value";
  }
  return "unknown";
}

/// @brief What the command line asked the program to do.
struct options {
  using value_type = std::string_view;

  std::string_view name{"world"};  ///< Who to greet.
  bool verbose{false};             ///< Whether to print the extra detail.
};

/**
 * @brief Parses the command line into an \c options.
 *
 * Recognises \c --name with a value and \c --verbose.
 *
 * @param arguments The arguments, without the program name.
 *
 * @return The parsed options, or the first error found.
 *
 * @pre None.
 * @post None.
 */
[[nodiscard]] constexpr auto parse(std::span<char const* const> const arguments) noexcept
  -> std::expected<options, option_error> {
  auto result{options{}};

  for (auto index{std::size_t{0}}; index < arguments.size(); ++index) {
    auto const argument{std::string_view{arguments[index]}};

    if (argument == "--verbose") {
      result.verbose = true;
    } else if (argument == "--name") {
      if (index + 1 >= arguments.size()) {
        return std::unexpected{option_error::missing_value};
      }
      ++index;
      result.name = std::string_view{arguments[index]};
    } else {
      return std::unexpected{option_error::unknown_flag};
    }
  }

  return result;
}

}  // namespace {{PROJECT}}
