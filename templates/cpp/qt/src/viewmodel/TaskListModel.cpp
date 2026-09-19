/**
 * @file
 * @brief Implements the list model over the task repository.
 */

#include "viewmodel/TaskListModel.hpp"

namespace {{PROJECT}}::viewmodel {

TaskListModel::TaskListModel(model::TaskRepository *repository, QObject *parent)
    : QAbstractListModel{parent}, m_repository{repository} {}

int TaskListModel::rowCount(const QModelIndex &parent) const {
  if (parent.isValid() || m_repository == nullptr) {
    return 0;
  }
  return static_cast<int>(m_repository->tasks().size());
}

QVariant TaskListModel::data(const QModelIndex &index, int role) const {
  if (!index.isValid() || m_repository == nullptr) {
    return {};
  }

  const auto &tasks = m_repository->tasks();
  if (index.row() < 0 || index.row() >= tasks.size()) {
    return {};
  }

  const model::Task &task = tasks.at(index.row());
  switch (role) {
    case TitleRole:
      return task.title;
    case DoneRole:
      return task.done;
    default:
      return {};
  }
}

QHash<int, QByteArray> TaskListModel::roleNames() const {
  return {
      {TitleRole, QByteArrayLiteral("title")},
      {DoneRole, QByteArrayLiteral("done")},
  };
}

void TaskListModel::refresh() {
  beginResetModel();
  endResetModel();
}

void TaskListModel::refreshRow(int index) {
  const QModelIndex changed = this->index(index, 0);
  if (changed.isValid()) {
    emit dataChanged(changed, changed, {TitleRole, DoneRole});
  }
}

}  // namespace {{PROJECT}}::viewmodel
