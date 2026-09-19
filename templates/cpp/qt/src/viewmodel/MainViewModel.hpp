#pragma once

/**
 * @file
 * @brief The view model behind the main window.
 */

#include <QObject>
#include <QQmlEngine>
#include <QString>

#include "model/TaskRepository.hpp"
#include "viewmodel/TaskListModel.hpp"

namespace {{PROJECT}}::viewmodel {

/**
 * @brief State and commands for the main view.
 *
 * The view binds to the properties and calls the invokable commands; it never
 * touches the repository. Everything the view needs to show is a property
 * here, so the view holds no logic of its own and this class can be tested
 * without a window.
 */
class MainViewModel : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_UNCREATABLE("MainViewModel is created by the application")

  // moc writes the type as it is spelt here and the registrar records the
  // class under its full name, so a bare TaskListModel leaves qmlls with
  // two names for one type and it resolves neither.
  Q_PROPERTY({{PROJECT}}::viewmodel::TaskListModel *tasks READ tasks CONSTANT)
  Q_PROPERTY(QString draftTitle READ draftTitle WRITE setDraftTitle NOTIFY draftTitleChanged)
  Q_PROPERTY(int remainingCount READ remainingCount NOTIFY tasksChanged)
  Q_PROPERTY(bool canAdd READ canAdd NOTIFY draftTitleChanged)

public:
  /**
   * @brief Builds a view model over \a repository.
   *
   * @param repository Storage the view model acts on; it must outlive it.
   * @param parent Owner in the QObject tree.
   */
  explicit MainViewModel(model::TaskRepository *repository, QObject *parent = nullptr);

  /**
   * @brief The list the view shows.
   *
   * @return The list model, owned by this view model.
   */
  [[nodiscard]] TaskListModel *tasks() const;

  /**
   * @brief What the user has typed but not yet added.
   *
   * @return The current draft title.
   */
  [[nodiscard]] QString draftTitle() const;

  /**
   * @brief Replaces the draft title.
   *
   * @param title The new draft; emits \a draftTitleChanged when it differs.
   */
  void setDraftTitle(const QString &title);

  /**
   * @brief How many tasks are still to do.
   *
   * @return The count of tasks not yet done.
   */
  [[nodiscard]] int remainingCount() const;

  /**
   * @brief Whether the draft can become a task.
   *
   * @return True when the draft is not blank.
   */
  [[nodiscard]] bool canAdd() const;

public slots:
  /**
   * @brief Turns the draft into a task and clears it.
   *
   * Does nothing when the draft is blank.
   */
  void addDraft();

  /**
   * @brief Flips one task between done and not done.
   *
   * @param index Position of the task in the list.
   */
  void toggle(int index);

  /**
   * @brief Drops every task already done.
   */
  void clearCompleted();

signals:
  /// @brief The draft title changed.
  void draftTitleChanged();

  /// @brief The task list changed: a task was added, removed or toggled.
  void tasksChanged();

private:
  model::TaskRepository *m_repository{nullptr};
  TaskListModel *m_tasks{nullptr};
  QString m_draftTitle;
};

}  // namespace {{PROJECT}}::viewmodel
