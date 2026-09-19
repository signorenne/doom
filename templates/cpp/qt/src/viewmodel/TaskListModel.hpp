#pragma once

/**
 * @file
 * @brief List model exposing the tasks to QML.
 */

#include <QAbstractListModel>
#include <QHash>
#include <QQmlEngine>

#include "model/TaskRepository.hpp"

namespace {{PROJECT}}::viewmodel {

/**
 * @brief Adapts the task repository to the list views in QML.
 *
 * It owns no data: the repository is passed in and stays the single source of
 * truth. The model only translates it into roles and emits the change
 * notifications QML needs.
 */
class TaskListModel : public QAbstractListModel {
  Q_OBJECT
  QML_ELEMENT
  QML_UNCREATABLE("TaskListModel comes from the view model")

public:
  /// @brief The roles a delegate can bind to.
  enum Role {
    TitleRole = Qt::UserRole + 1,  ///< The task title, as a string.
    DoneRole,                      ///< Whether the task is done, as a bool.
  };
  Q_ENUM(Role)

  /**
   * @brief Builds a model over \a repository.
   *
   * @param repository Storage the model reads; it must outlive the model.
   * @param parent Owner in the QObject tree.
   */
  explicit TaskListModel(model::TaskRepository *repository, QObject *parent = nullptr);

  /**
   * @brief How many tasks the view should show.
   *
   * @param parent Parent index; a list has items only at the root.
   *
   * @return The task count, or zero for a non-root parent.
   */
  [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;

  /**
   * @brief The value of one role for one task.
   *
   * @param index Position of the task.
   * @param role One of \a Role.
   *
   * @return The requested value, or an invalid variant when the index or the
   *         role is out of range.
   */
  [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;

  /**
   * @brief Names the roles so QML can bind to them by name.
   *
   * @return The role to name mapping.
   */
  [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

  /**
   * @brief Re-reads the repository and tells the views everything changed.
   *
   * Called by the view model after an operation that can add or remove rows.
   */
  void refresh();

  /**
   * @brief Tells the views that one task changed in place.
   *
   * @param index Position of the task that changed.
   */
  void refreshRow(int index);

private:
  model::TaskRepository *m_repository{nullptr};
};

}  // namespace {{PROJECT}}::viewmodel
