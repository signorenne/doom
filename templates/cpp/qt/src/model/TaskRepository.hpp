#pragma once

/**
 * @file
 * @brief Storage for the tasks, with no dependency on the view.
 */

#include <QList>

#include "model/Task.hpp"

namespace {{PROJECT}}::model {

/**
 * @brief Holds the tasks and the operations on them.
 *
 * The repository is the only place that knows how tasks are stored. Swap it
 * for one backed by a file or a service and neither the view models nor the
 * QML change.
 */
class TaskRepository {
public:
  /**
   * @brief Every task, in insertion order.
   *
   * @return A const reference to the stored tasks.
   */
  [[nodiscard]] const QList<Task> &tasks() const;

  /**
   * @brief Appends a task with the given title.
   *
   * @param title Title of the new task; a blank title is refused.
   *
   * @return True when a task was added.
   */
  bool add(const QString &title);

  /**
   * @brief Flips the done state of one task.
   *
   * @param index Position of the task.
   *
   * @return True when the index was in range.
   */
  bool toggle(int index);

  /**
   * @brief Removes every task already done.
   *
   * @return How many tasks were removed.
   */
  int clearCompleted();

  /**
   * @brief How many tasks are still to do.
   *
   * @return The count of tasks whose done state is false.
   */
  [[nodiscard]] int remainingCount() const;

private:
  QList<Task> m_tasks;
};

}  // namespace {{PROJECT}}::model
