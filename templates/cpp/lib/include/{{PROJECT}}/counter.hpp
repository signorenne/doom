#pragma once

/**
 * @file
 * @brief A counter that reports overflow instead of wrapping.
 */

#include <compare>
#include <concepts>
#include <cstdint>
#include <expected>
#include <limits>

namespace {{PROJECT}} {

/// @brief Why a counter operation failed.
enum class counter_error : std::uint8_t {
  overflow,   ///< The addition would pass the maximum of the counter type.
  underflow,  ///< The subtraction would take the count below zero.
};

/**
 * @brief Turns a \c counter_error into a readable name.
 *
 * @param error The error to name.
 *
 * @return A static string naming the error.
 *
 * @pre None.
 * @post None.
 */
[[nodiscard]] constexpr auto to_string(counter_error const error) noexcept -> char const* {
  switch (error) {
    case counter_error::overflow:
      return "overflow";
    case counter_error::underflow:
      return "underflow";
  }
  return "unknown";
}

/**
 * @brief A counter that reports its limits instead of wrapping.
 *
 * Both operations return \c std::expected, so a caller sees the failure in
 * the return type rather than through an exception or a silent wrap.
 *
 * @tparam T Unsigned integral counter type.
 *
 * @pre None.
 * @post A default-constructed counter is zero.
 */
template <std::unsigned_integral T>
class counter {
public:
  using value_type = T;

private:
  value_type m_value{};

public:
  // Rule of zero: the compiler's special members are correct here.

  /**
   * @brief The current count.
   *
   * @return The stored value.
   *
   * @pre None.
   * @post None.
   */
  [[nodiscard]] constexpr auto value() const noexcept -> value_type {
    return m_value;
  }

  /**
   * @brief Adds \p amount, reporting overflow instead of wrapping.
   *
   * @param amount Amount to add.
   *
   * @return The new count, or \c counter_error::overflow when the addition
   *         would exceed the maximum of \p T.
   *
   * @pre None.
   * @post On success the count has grown by \p amount; on failure it is
   *       unchanged.
   */
  [[nodiscard]] constexpr auto add(value_type const amount) noexcept
    -> std::expected<value_type, counter_error> {
    if (amount > std::numeric_limits<value_type>::max() - m_value) {
      return std::unexpected{counter_error::overflow};
    }
    // Through the widest unsigned type: for a value_type narrower than
    // int the operands promote and the cast back is needed, for a wider
    // one it would be a cast to the type it already has, which GCC calls
    // a useless cast and the ci preset turns into an error.
    m_value = static_cast<value_type>(static_cast<std::uintmax_t>(m_value)
                                      + static_cast<std::uintmax_t>(amount));
    return m_value;
  }

  /**
   * @brief Subtracts \p amount, reporting underflow instead of wrapping.
   *
   * @param amount Amount to subtract.
   *
   * @return The new count, or \c counter_error::underflow when the
   *         subtraction would take it below zero.
   *
   * @pre None.
   * @post On success the count has fallen by \p amount; on failure it is
   *       unchanged.
   */
  [[nodiscard]] constexpr auto subtract(value_type const amount) noexcept
    -> std::expected<value_type, counter_error> {
    if (amount > m_value) {
      return std::unexpected{counter_error::underflow};
    }
    m_value = static_cast<value_type>(static_cast<std::uintmax_t>(m_value)
                                      - static_cast<std::uintmax_t>(amount));
    return m_value;
  }

  /**
   * @brief Resets the count to zero.
   *
   * @pre None.
   * @post The count is zero.
   */
  constexpr auto reset() noexcept -> void {
    m_value = value_type{};
  }

  /**
   * @brief Equality of two counters; the compiler derives \c != from it.
   *
   * @param lhs Left operand.
   * @param rhs Right operand.
   *
   * @return True when both hold the same count.
   *
   * @pre None.
   * @post None.
   */
  [[nodiscard]] friend constexpr auto operator==(counter const& lhs, counter const& rhs) noexcept
    -> bool = default;

  /**
   * @brief Ordering of two counters; the compiler derives the rest.
   *
   * @param lhs Left operand.
   * @param rhs Right operand.
   *
   * @return The ordering of the two counts.
   *
   * @pre None.
   * @post None.
   */
  [[nodiscard]] friend constexpr auto
  operator<=>(counter const& lhs, counter const& rhs) noexcept = default;
};

}  // namespace {{PROJECT}}
