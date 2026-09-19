#pragma once

/**
 * @file
 * @brief The one thing this application is about: a task.
 */

#include <QString>

namespace {{PROJECT}}::model {

/**
 * @brief A task, as the domain sees it.
 *
 * Plain data with no QObject and no signals: the model layer knows nothing
 * about the view or about QML, which is what lets it be tested on its own.
 */
struct Task {
  QString title;     ///< What is to be done.
  bool done{false};  ///< Whether it has been done.

  /**
   * @brief Compares two tasks field by field.
   *
   * @param lhs Left operand.
   * @param rhs Right operand.
   *
   * @return True when the title and the state match.
   */
  [[nodiscard]] friend bool operator==(const Task &lhs, const Task &rhs) = default;
};

}  // namespace {{PROJECT}}::model
