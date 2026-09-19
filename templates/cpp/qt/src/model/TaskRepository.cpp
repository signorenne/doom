/**
 * @file
 * @brief Implements the task storage.
 */

#include "model/TaskRepository.hpp"

#include <algorithm>

namespace {{PROJECT}}::model {

const QList<Task> &TaskRepository::tasks() const {
  return m_tasks;
}

bool TaskRepository::add(const QString &title) {
  const QString trimmed = title.trimmed();
  if (trimmed.isEmpty()) {
    return false;
  }
  m_tasks.append(Task{.title = trimmed, .done = false});
  return true;
}

bool TaskRepository::toggle(int index) {
  if (index < 0 || index >= m_tasks.size()) {
    return false;
  }
  m_tasks[index].done = !m_tasks[index].done;
  return true;
}

int TaskRepository::clearCompleted() {
  const auto removed = m_tasks.removeIf([](const Task &task) { return task.done; });
  return static_cast<int>(removed);
}

int TaskRepository::remainingCount() const {
  return static_cast<int>(std::ranges::count_if(m_tasks, [](const Task &task) {
    return !task.done;
  }));
}

}  // namespace {{PROJECT}}::model
