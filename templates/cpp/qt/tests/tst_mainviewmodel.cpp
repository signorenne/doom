/**
 * @file
 * @brief Tests for the main view model, with no window in sight.
 */

#include <QSignalSpy>
#include <QTest>

#include "model/TaskRepository.hpp"
#include "viewmodel/MainViewModel.hpp"

using {{PROJECT}}::model::TaskRepository;
using {{PROJECT}}::viewmodel::MainViewModel;
using {{PROJECT}}::viewmodel::TaskListModel;

/**
 * @brief Exercises the commands and the notifications the view binds to.
 */
class TestMainViewModel : public QObject {
  Q_OBJECT

private slots:
  void addsTheDraftAndClearsIt();
  void refusesABlankDraft();
  void togglingChangesTheRemainingCount();
  void clearCompletedRemovesTheDoneTasks();
  void theListModelExposesTitleAndDone();
};

void TestMainViewModel::addsTheDraftAndClearsIt() {
  TaskRepository repository;
  MainViewModel viewModel{&repository};
  const QSignalSpy tasksChanged{&viewModel, &MainViewModel::tasksChanged};

  viewModel.setDraftTitle(QStringLiteral("write a test"));
  QVERIFY(viewModel.canAdd());
  viewModel.addDraft();

  QCOMPARE(tasksChanged.count(), 1);
  QCOMPARE(repository.tasks().size(), 1);
  QCOMPARE(repository.tasks().first().title, QStringLiteral("write a test"));
  QVERIFY(viewModel.draftTitle().isEmpty());
}

void TestMainViewModel::refusesABlankDraft() {
  TaskRepository repository;
  MainViewModel viewModel{&repository};

  viewModel.setDraftTitle(QStringLiteral("   "));
  QVERIFY(!viewModel.canAdd());
  viewModel.addDraft();

  QVERIFY(repository.tasks().isEmpty());
}

void TestMainViewModel::togglingChangesTheRemainingCount() {
  TaskRepository repository;
  repository.add(QStringLiteral("one"));
  MainViewModel viewModel{&repository};

  QCOMPARE(viewModel.remainingCount(), 1);
  viewModel.toggle(0);
  QCOMPARE(viewModel.remainingCount(), 0);
}

void TestMainViewModel::clearCompletedRemovesTheDoneTasks() {
  TaskRepository repository;
  repository.add(QStringLiteral("one"));
  repository.add(QStringLiteral("two"));
  MainViewModel viewModel{&repository};

  viewModel.toggle(0);
  viewModel.clearCompleted();

  QCOMPARE(repository.tasks().size(), 1);
  QCOMPARE(repository.tasks().first().title, QStringLiteral("two"));
}

void TestMainViewModel::theListModelExposesTitleAndDone() {
  TaskRepository repository;
  repository.add(QStringLiteral("one"));
  MainViewModel viewModel{&repository};

  TaskListModel *tasks = viewModel.tasks();
  QCOMPARE(tasks->rowCount(), 1);

  const QModelIndex first = tasks->index(0, 0);
  QCOMPARE(tasks->data(first, TaskListModel::TitleRole).toString(), QStringLiteral("one"));
  QCOMPARE(tasks->data(first, TaskListModel::DoneRole).toBool(), false);
  QVERIFY(tasks->roleNames().values().contains(QByteArrayLiteral("title")));
}

QTEST_MAIN(TestMainViewModel)

#include "tst_mainviewmodel.moc"
