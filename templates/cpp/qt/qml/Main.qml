// The window. It receives the view model from C++ as a required property and
// passes it down; no view constructs its own view model.
import QtQuick
import QtQuick.Controls
import {{PROJECT}}

ApplicationWindow {
  id: window

  required property MainViewModel viewModel

  width: 480
  height: 640
  visible: true
  title: qsTr("{{PROJECT}}")

  TaskListView {
    anchors.fill: parent
    viewModel: window.viewModel
  }
}
