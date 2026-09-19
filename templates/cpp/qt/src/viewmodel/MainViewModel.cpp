/**
 * @file
 * @brief Implements the main view model.
 */

#include "viewmodel/MainViewModel.hpp"

namespace {{PROJECT}}::viewmodel {

MainViewModel::MainViewModel(model::TaskRepository *repository, QObject *parent)
    : QObject{parent}, m_repository{repository}, m_tasks{new TaskListModel{repository, this}} {}

TaskListModel *MainViewModel::tasks() const {
  return m_tasks;
}

QString MainViewModel::draftTitle() const {
  return m_draftTitle;
}

void MainViewModel::setDraftTitle(const QString &title) {
  if (m_draftTitle == title) {
    return;
  }
  m_draftTitle = title;
  emit draftTitleChanged();
}

int MainViewModel::remainingCount() const {
  return m_repository == nullptr ? 0 : m_repository->remainingCount();
}

bool MainViewModel::canAdd() const {
  return !m_draftTitle.trimmed().isEmpty();
}

void MainViewModel::addDraft() {
  if (m_repository == nullptr || !m_repository->add(m_draftTitle)) {
    return;
  }
  m_tasks->refresh();
  setDraftTitle({});
  emit tasksChanged();
}

void MainViewModel::toggle(int index) {
  if (m_repository == nullptr || !m_repository->toggle(index)) {
    return;
  }
  m_tasks->refreshRow(index);
  emit tasksChanged();
}

void MainViewModel::clearCompleted() {
  if (m_repository == nullptr || m_repository->clearCompleted() == 0) {
    return;
  }
  m_tasks->refresh();
  emit tasksChanged();
}

}  // namespace {{PROJECT}}::viewmodel
