// The view: layout and bindings only. Every piece of state it shows is a
// property of the view model, and every action calls one of its commands.
// A delegate is its own component, so an id from outside it is an
// unqualified name unless this is said; Qt has wanted it since 6.7.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import {{PROJECT}}

Item {
  id: root

  required property MainViewModel viewModel

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 12

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      TextField {
        id: draftField
        Layout.fillWidth: true
        placeholderText: qsTr("What needs doing?")
        text: root.viewModel.draftTitle
        onTextEdited: root.viewModel.draftTitle = text
        onAccepted: root.viewModel.addDraft()
      }

      Button {
        text: qsTr("Add")
        enabled: root.viewModel.canAdd
        onClicked: root.viewModel.addDraft()
      }
    }

    ListView {
      id: taskList

      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 4
      model: root.viewModel.tasks

      delegate: CheckDelegate {
        required property int index
        required property string title
        required property bool done

        width: taskList.width
        text: title
        checked: done
        onToggled: root.viewModel.toggle(index)
      }
    }

    RowLayout {
      Layout.fillWidth: true

      Label {
        Layout.fillWidth: true
        text: qsTr("%n left", "", root.viewModel.remainingCount)
      }

      Button {
        text: qsTr("Clear done")
        onClicked: root.viewModel.clearCompleted()
      }
    }
  }
}
