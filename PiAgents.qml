import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "../theme"

BarButton {
	id: root

	readonly property string scriptPath: Quickshell.shellDir + "/scripts/pi-agents.py"
	readonly property color tone: root.stateColor(root.agentState)

	property string agentState: "idle"
	property var agents: []

	icon: root.stateIcon(root.agentState)
	iconColor: root.tone
	iconSize: 13
	hPadding: 5
	spacing: 3
	value: `${root.agents.length}`
	valueColor: root.tone

	function stateIcon(state) {
		const icons = { idle: "\uf4b8", working: "\uf110", asking: "\uf059", error: "\uf071" };
		return icons[state] || icons.idle;
	}

	function stateColor(state) {
		const colors = { idle: Theme.muted, working: Theme.accent, asking: Theme.tertiary, error: Theme.alert };
		return colors[state] || Theme.muted;
	}

	function normalize(state) {
		if (state === "idle" || state === "working" || state === "asking" || state === "error")
			return state;
		return "error";
	}

	function parseAgent(entry) {
		if (!entry || typeof entry.name !== "string" || entry.name.trim() === "")
			return null;
		const depth = Number.isFinite(entry.depth) ? Math.min(4, Math.max(0, Math.floor(entry.depth))) : 0;
		return { name: entry.name.trim(), state: root.normalize(entry.state), depth: depth };
	}

	function sameAgents(left, right) {
		if (left.length !== right.length) return false;

		for (let i = 0; i < left.length; i++) {
			if (left[i].name !== right[i].name || left[i].state !== right[i].state || left[i].depth !== right[i].depth)
				return false;
		}
		return true;
	}

	function apply(text) {
		let payload = null;
		try {
			payload = JSON.parse(text);
		} catch (error) {
			payload = null;
		}

		if (!payload || !Array.isArray(payload.rows)) {
			if (root.agents.length > 0) root.agents = [];
			if (root.agentState !== "error") root.agentState = "error";
			return;
		}

		const parsed = [];
		for (const entry of payload.rows) {
			const agent = root.parseAgent(entry);
			if (agent !== null)
				parsed.push(agent);
		}
		let nextState = root.normalize(payload.state);
		if (nextState !== "error" && parsed.length === 0)
			nextState = "idle";

		if (!root.sameAgents(root.agents, parsed)) root.agents = parsed;
		if (root.agentState !== nextState) root.agentState = nextState;
	}

	readonly property Process poller: Process {
		command: ["python3", root.scriptPath]
		stdout: StdioCollector {
			id: collector
			waitForEnd: true
			onStreamFinished: root.apply(collector.text)
		}
	}

	Timer {
		interval: 1000
		running: true
		repeat: true
		triggeredOnStart: true
		onTriggered: {
			if (root.poller.running)
				return;
			root.poller.exec(root.poller.command);
		}
	}

	PopupWindow {
		id: popup

		property bool shown: false
		property bool pointerInside: false

		visible: popup.shown
		color: "transparent"
		implicitWidth: 300
		implicitHeight: content.implicitHeight + 24

		anchor.item: root
		anchor.edges: Edges.Bottom | Edges.Left
		anchor.gravity: Edges.Bottom | Edges.Right
		anchor.adjustment: PopupAdjustment.SlideX
		anchor.margins.top: 8

		Connections {
			target: root
			function onHoveredChanged() {
				if (root.hovered) {
					closeTimer.stop();
					openTimer.restart();
				} else {
					openTimer.stop();
					closeTimer.restart();
				}
			}
		}

		Timer {
			id: openTimer
			interval: 160
			onTriggered: popup.shown = true
		}

		Timer {
			id: closeTimer
			interval: 240
			onTriggered: {
				if (!root.hovered && !popup.pointerInside)
					popup.shown = false;
			}
		}

		Rectangle {
			anchors.fill: parent
			color: Theme.popup
			border.width: 1
			border.color: Theme.popupBorder
			radius: 12

			HoverHandler {
				id: cardHover
				onHoveredChanged: {
					popup.pointerInside = cardHover.hovered;
					if (cardHover.hovered) {
						openTimer.stop();
						closeTimer.stop();
						popup.shown = true;
					} else if (!root.hovered) {
						closeTimer.restart();
					}
				}
			}

			Column {
				id: content

				x: 14
				y: 12
				width: popup.width - 28
				spacing: 8

				Item {
					width: parent.width
					height: 20

					Text {
						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						text: "pi agents"
						textFormat: Text.PlainText
						color: Theme.muted
						font.family: Theme.fontUi
						font.pixelSize: Theme.microSize
						font.weight: Font.Medium
					}

					Text {
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						text: root.agentState
						textFormat: Text.PlainText
						color: root.tone
						font.family: Theme.fontUi
						font.pixelSize: Theme.microSize
						font.weight: Font.Medium
					}
				}

				Rectangle {
					width: parent.width
					height: 1
					color: Theme.track
				}

				Text {
					visible: root.agents.length === 0
					text: root.agentState === "error" ? "agent state unavailable" : "no active agents"
					textFormat: Text.PlainText
					color: Theme.faint
					font.family: Theme.fontUi
					font.pixelSize: Theme.microSize
				}

				Item {
					visible: root.agents.length > 0
					width: parent.width
					height: Math.min(list.contentHeight, 264)

					ListView {
						id: list

						anchors.fill: parent
						anchors.rightMargin: 8
						clip: true
						boundsBehavior: Flickable.StopAtBounds
						model: root.agents

						delegate: Item {
							id: agentRow

							required property var modelData

							width: list.width
							height: 24

							Text {
								id: stateGlyph

								x: agentRow.modelData.depth * 12
								anchors.verticalCenter: parent.verticalCenter
								width: 14
								text: root.stateIcon(agentRow.modelData.state)
								color: root.stateColor(agentRow.modelData.state)
								font.family: Theme.fontMono
								font.pixelSize: 11
							}

							Text {
								id: stateWord

								anchors.right: parent.right
								anchors.verticalCenter: parent.verticalCenter
								text: agentRow.modelData.state
								textFormat: Text.PlainText
								color: root.stateColor(agentRow.modelData.state)
								font.family: Theme.fontUi
								font.pixelSize: 11
								font.weight: Font.Medium
							}

							Text {
								anchors.left: stateGlyph.right
								anchors.leftMargin: 6
								anchors.right: stateWord.left
								anchors.rightMargin: 8
								anchors.verticalCenter: parent.verticalCenter
								text: agentRow.modelData.name
								textFormat: Text.PlainText
								elide: Text.ElideRight
								color: agentRow.modelData.depth === 0 ? Theme.text : Theme.muted
								font.family: Theme.fontUi
								font.pixelSize: 12
								font.weight: agentRow.modelData.depth === 0 ? Font.Medium : Font.Normal
							}
						}
					}

					Rectangle {
						visible: list.contentHeight > list.height + 1
						x: parent.width - 2
						y: list.height * list.visibleArea.yPosition
						width: 2
						height: Math.max(16, list.height * list.visibleArea.heightRatio)
						radius: 1
						color: Theme.track
					}
				}
			}
		}
	}
}
