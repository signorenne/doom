/**
 * @file
 * @brief Composition root: builds the model, the view model and the engine.
 *
 * The application owns the repository and the view model and hands the view
 * model to QML as an initial property, so the QML never constructs C++ objects
 * and never reaches for a global.
 */

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

#include "model/TaskRepository.hpp"
#include "viewmodel/MainViewModel.hpp"

auto main(int argc, char *argv[]) -> int {
  QGuiApplication app{argc, argv};
  QGuiApplication::setApplicationName(QStringLiteral("{{PROJECT}}"));
  QQuickStyle::setStyle(QStringLiteral("Basic"));

  {{PROJECT}}::model::TaskRepository repository;
  repository.add(QStringLiteral("Read the style guide"));
  repository.add(QStringLiteral("Wire a view model"));

  {{PROJECT}}::viewmodel::MainViewModel viewModel{&repository};

  QQmlApplicationEngine engine;
  engine.setInitialProperties({{QStringLiteral("viewModel"), QVariant::fromValue(&viewModel)}});
  QObject::connect(
      &engine,
      &QQmlApplicationEngine::objectCreationFailed,
      &app,
      [] { QCoreApplication::exit(EXIT_FAILURE); },
      Qt::QueuedConnection
  );
  engine.loadFromModule("{{PROJECT}}", "Main");

  return QGuiApplication::exec();
}
