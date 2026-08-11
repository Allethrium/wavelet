const REALTIME_CONFIG = {
	// Sets us up for websockets if it is available
	USE_WEBSOCKETS: false, // Set to true when WebSocket server is deployed
	WS_URL: `wss://${window.location.host}/ws`,
	SSE_URL: '/sse_client.php'
};

function escapeHTML(val) {
	let text = val === undefined || val === null ? '' : String(val);
	let map = {
		'&': '&amp;',
		'<': '&lt;',
		'>': '&gt;',
		'"': '&quot;',
		"'": '&#039;'
	};
	return text.replace(/[&<>"']/g, function (m) {
		return map[m];
	});
}


//
//
// Classes
//
//


class Group {
	// The Group class is the system basic primitive, and the most complex object we deal with in the system.
	constructor(data) {
		this.type = data.type || "group";
		this.hashID = data.hashID;
		this.element = null;
		this.controls = data.controls || {};
		this.inputs = new Map(); // Initialize a map to track all inputs in this group
		this.inputButtonMap = new Map(); // A map of input button elements within the group
		this._sourceHash = data.controls?.sourceHash || null;
		this.emitter = new EventEmitter();
		this.inputs.set('0', {
			hashID: '0',
			labelText: 'Black Screen',
			element: null,       // no DOM element yet
			parentHashID: this.hashID
		});
		this.inputs.set('1', {
			hashID: '1',
			labelText: 'Static Image',
			element: null,
			parentHashID: this.hashID
		});
		this.inputs.set('2', {
			hashID: '2',
			labelText: 'Test Card',
			element: null,
			parentHashID: this.hashID
		});
	}
	get sourceHash() {
		return this._sourceHash;
	}
	set sourceHash(value) {
		const previousHash = this._sourceHash;
		this._sourceHash = value;
		this.controls.sourceHash = value;
		// console.log(`Group ${this.hashID}: sourceHash changed from ${previousHash || 'null'} → ${value}`);
		// Update UI state (DOM elements, active buttons, etc.)
		this.updateActiveState();
		// Emit local event for subscribers
		this.emitter.emit('activeInputChange', {
			newValue: value,
			oldValue: previousHash
		});
		// Notify global listeners (dropdown refresh, registry updates, etc.)
		if (window.root?.activeGroupInputsEmitter) {
			window.root.activeGroupInputsEmitter.emit(this.hashID);
		}
		// Dispatch a global event for DOM-bound logic
		if (this.element) {
			document.dispatchEvent(new CustomEvent('sourceDropdownRefresh', {detail: this}));
		}
	}
	handleSourceChange(selectedValue) {
		// Handles the logic for switching to a new source (input or another group)
		// Split composite value (e.g., "1:2" → groupHash=1, inputHash=2)
		const parts = selectedValue.split(':');
		const targetGroup = parts[0] || null; // groupHash (null for local)
		const targetHash = parts[1] || selectedValue; // inputHash
		const group = this;
		console.debug(`Handling source change for group: ${targetGroup}, with source hash: ${targetHash}`);
		// Find which group owns this source
		// inputOwnerGroupHash is always defined from targetGroup
		let inputOwnerGroupHash = targetGroup || group.hashID;
		// Determine if we need to update the chain
		let shouldUpdateChain = false;
		if (inputOwnerGroupHash !== group.hashID) {
			// External source – chain to that group
			if (!group.isChained() || group.controls.chainedToGroup !== inputOwnerGroupHash) {
				shouldUpdateChain = true;
				void window.root.controlRequestManager.send({
					operation: "GROUPCONTROL",
					parentHash: group.hashID,
					parentType: "group",
					controlKey: "chainedToGroup",
					controlValue: inputOwnerGroupHash,
					toggleOn: false
				});
				group.controls.chainedToGroup = inputOwnerGroupHash;
			}
		} else {
			// Local or self-reference – break chain if needed
			if (group.isChained()) {
				shouldUpdateChain = true;
				group.controls.chainedToGroup = null;
			}
			// Always propagate the newly selected local source to the backend
			void window.root.controlRequestManager.send({
				operation: "GROUPCONTROL",
				parentHash: group.hashID,
				parentType: "group",
				controlKey: "changeGroupSource",
				controlValue: targetHash,
				toggleOn: false
			});
		}
		// Update sourceHash using the setter
		this.controls.sourceHash = selectedValue;
		// update this group's source DropDown.
		document.dispatchEvent(new CustomEvent('sourceDropdownRefresh', {detail: this}));
		// Refresh external group if chained
		if (shouldUpdateChain && inputOwnerGroupHash && inputOwnerGroupHash !== group.hashID) {
			const externalGroup = window.root.groups.get(inputOwnerGroupHash);
			if (externalGroup) {
				externalGroup.updateActiveState();
				if (externalGroup.element) {
					document.dispatchEvent(new CustomEvent('sourceDropdownRefresh', {detail: externalGroup}));
				}
			}
		}
	}
	isChained() {
		return this.controls?.chainedToGroup !== null &&
			this.controls?.chainedToGroup !== 'null' &&
			this.controls?.chainedToGroup !== undefined &&
			this.controls?.chainedToGroup !== '';
	}
	registerGroupInput(inputInstance) {
		this.inputs.set(inputInstance.hashID, inputInstance);
		// console.log(`Input ${inputInstance.labelText} registered in Group ${this.hashID}:`);
		if (window.root && !window.root.activeGroupInputsEmitter) {
			window.root.activeGroupInputsEmitter = new EventEmitter();
		}
		// Rebuild the input button cache since new inputs may have been added
		this.inputButtonMap.clear();
		this.updateActiveState();
	}
	async setActiveInput(hashID) {
		// If this group is chained to another group, break the chain when selecting a local source
		if (this.controls.chainedToGroup !== null && this.inputs.has(hashID)) {
			console.log(`Group ${this.hashID}: Breaking chain before setting local source ${hashID}`);
			await window.root.controlRequestManager.send({
				operation: "GROUPCONTROL",
				parentHash: this.hashID,
				parentType: "group",
				controlKey: "chainedToGroup",
				controlValue: null,
				toggleOn: false
			});
			this.controls.chainedToGroup = null;
		}
		await window.root.controlRequestManager.send({
			operation: "GROUPCONTROL",
			parentHash: this.hashID,
			parentType: "group",
			controlKey: "changeGroupSource",
			controlValue: hashID,
			toggleOn: false
		});
		// this.controls.sourceHash = hashID;
		// SSE will handle everything on the return pass
	}
	updateActiveState() {
		const group = this;
		if (!group.element) return;
		// Build the button cache once
		if (!group.inputButtonMap.size) {
			const buttons = group.element.querySelectorAll('.btn[data-type="INPUT"]');
			buttons.forEach(btn => {
				const value = btn.dataset.parentHash;
				group.inputButtonMap.set(value, btn);
			});
		}
		if (group.isChained()) {
			group.inputButtonMap.forEach(btn => btn.removeAttribute('data-active'));
		} else {
			group.inputButtonMap.forEach(btn => btn.removeAttribute('data-active'));
			const activeBtn = group.inputButtonMap.get(group.controls.sourceHash);
			if (activeBtn && activeBtn.dataset.value !== "relabel") {
				activeBtn.setAttribute('data-active', '1');
				console.log(`Group ${group.hashID}: marked input ${group.controls.sourceHash} as active`);
			}
		}
		// Force a reflow to ensure the attribute is applied
		group.inputButtonMap.forEach(btn => {
			if (btn.hasAttribute('data-active')) {
				void btn.offsetWidth;
			}
		});
	}
	unregisterGroup(hashID) {
		// Remove from the global groups registry
		window.root.groups.delete(hashID);
		console.log("Registry removed group:", hashID);
		// Clean up all emitter subscriptions on this group's DOM elements
		if (this.element) {
			const cleanupFunctions = this.element.querySelectorAll('[data-parent-hash]');
			cleanupFunctions.forEach(el => {
				if (el._cleanupEmitter) el._cleanupEmitter();
			});
		}
		// Clear the emitter itself to release all stored callbacks
		this.emitter.listeners.clear();
		// Notify global listeners to refresh ALL source dropdowns
		if (window.root && window.root.activeGroupInputsEmitter) {
			window.root.activeGroupInputsEmitter.emit('*');
		}
		// Remove the group from local inputs as well
		this.inputs.clear();
	}
	unregisterInput(inputInstance) {
		this.inputs.delete(inputInstance.hashID);
		console.log(`Input removed from Group ${this.hashID}:`, inputInstance.hashID);
		// Clean up emitter subscriptions on this input's DOM elements
		if (inputInstance.element && inputInstance.element._cleanupEmitter) {
			inputInstance.element._cleanupEmitter();
		}
		// Emit event for input removal
		this.emitter.emit('inputUnregistered', inputInstance.hashID);
		// Notify global listeners to refresh source dropdowns
		if (window.root && window.root.activeGroupInputsEmitter) {
			window.root.activeGroupInputsEmitter.emit(this.hashID);
		}
	}
}

class Host {
	// The host class, replacing the old data object technique
	constructor(data) {
		this.hashID = data.hashID;
		this.controls = data.controls || {}; // hostType and most other data are in controls
		this.lastUpdate = Date.now();
		this.ipAddress = data.ipAddress || null;
		this.hostType = data.controls.type;  // SVR, DEC, ENC, NDI, RTSP, other
		this.type = data.type; // Host, net, infra
		this.inputs = new Map(); // An input source MUST be on a host and also must register in the group instance.
		this.emitter = new EventEmitter();
		this.element = null; // Assigned when createHostElement() attaches the host's DOM element
	}
	async changeGroup(newGroupHash) {
		// Moves this host instance and element to another group.  Automatically registers any inputs on this host.
		const oldGroupHash = this.controls.GROUP;
		const newGroupInstance = window.root.groups.get(newGroupHash);
		const oldGroupInstance = window.root.groups.get(oldGroupHash);
		// Update backend control before updating UI
		if (newGroupHash && newGroupHash !== oldGroupHash) {
			await window.root.controlRequestManager.send({
				operation: "HOSTCONTROL",
				parentHash: this.hashID,
				parentType: "host",
				controlKey: "changeGroup",
				controlValue: newGroupHash,
				toggleOn: false
			});
			this.controls.GROUP = newGroupHash;
		}
		// Move the host DOM element to the new group
		if (newGroupInstance && newGroupInstance.element) {
			newGroupInstance.element.appendChild(this.element);
		}
		// Handle input re-registration if group changed
		if (newGroupHash !== oldGroupHash && newGroupInstance) {
			// Update the uiContainer reference for inputs to the new group container
			this.uiContainer = newGroupInstance.element;
			// Re-register all inputs with the new group
			for (const [inputInstance] of this.inputs) {
				// Remove from old group
				if (oldGroupInstance) {
					oldGroupInstance.unregisterInput(inputInstance);
				}
				// Register with new group
				newGroupInstance.registerGroupInput(inputInstance);
			}
		}
	}
	createHostButtonSet() {
		// Responsible for generating all appropriate buttons for the host div
		// Create the div for everything to reside within
		const container = document.createElement("div");
		// Create the div for the buttons and health indicator to reside within
		const buttonsDiv = document.createElement("div");
		container.classList.add("buttons_container");
		buttonsDiv.classList.add("host-buttons");
		// Each host has a label text box, which sets the pretty host name
		buttonsDiv.appendChild(createHealthIndicator(this));
		if (window.root.globals.lowInformationMode === false) {
			// console.log(`creating advanced options for: ${this.controls.label}`);
			// lowInformationMode is off
			// Add the detail menu for advanced controls
			container.appendChild(createTextBox(this, "HOST:", "label"));
			const hostDetailMenu = createDetailMenu(this);
			buttonsDiv.appendChild(hostDetailMenu);
			// addEmitterListener(hostDetailMenu, this, 'menu');
		} else {
			// lowInformationMode is active
			// Fewer controls - no detail menu, host textbox is not editable.
			container.appendChild(document.createTextNode(`HOST: ${escapeHTML(this.controls.label)}`));
		}
		// Every client gets a health status indicator
		// Blank control button is added in both modes UNLESS we are a net device
		// console.log("Host data:" + element.dataset.host);
		if (this.hostType === "net" || this.hostType === "svr") {
			console.info("Net host or server detected, not generating blank button..");
			// perhaps change the color style here to differentiate it from wavelet hosts
		} else {
			if (this.hostType !== "net" && this.hostType !== "svr") {
				const blankButton = createUnifiedButton({
					parentItem: this,
					parentHash: this.hashID,
					groupHash: this.controls.GROUP,
					control: "blankStatus",
					title: "Toggle video display output on this host",
					dataLabel: "⬛ BLANK",
					operation: "HOSTCONTROL",
					value: this.controls.blankStatus,
					buttonCategory: "HOST",
					toggleOn: true
				});
				buttonsDiv.appendChild(blankButton);
				addEmitterListener(blankButton, this, 'blankStatus');
				const uiNotifierDiv = createUINotifier(this);
				addEmitterListener(uiNotifierDiv, this, "UIEnable");
			}
		}
		if ((this.controls.type === "ENC" || this.controls.type === "svr")) {
			this.encNotifier = createENCNotifier(this);
			buttonsDiv.appendChild(this.encNotifier);
		}
		if (this.type === "NDI") {
			this.ndiNotifier = createNDINotifier(this);
			buttonsDiv.appendChild(this.ndiNotifier);
		}
		if (this.type === "RTSP") {
			this.rtspNotifier = createRTSPNotifier(this);
			buttonsDiv.appendChild(this.rtspNotifier);
		}
		if (this.controls.UIEnable === "1") {
			buttonsDiv.appendChild(createUINotifier(this));
		}
		container.appendChild(buttonsDiv);
		return container;
	}
	registerHostInput(inputInstance) {
		// Registers the class instance with the host, group and generates the DOM element.
		let newInputElement;
		console.info("Registering new host input: ", inputInstance.hashID);
		newInputElement = createInputElement(inputInstance);
		inputInstance.element = newInputElement;
		// console.log("registerHostInput for", inputInstance.hashID,
		// 	"uiContainer:", this.uiContainer,
		// 	"uiContainer.parentNode:", this.uiContainer?.parentNode);
		this.emitter.emit('inputCreated', inputInstance);
		if (this.uiContainer) {
			console.info("Found UI element in host, appending input element..");
			this.uiContainer.appendChild(inputInstance.element);
		} else {
			console.info("No UI element found in host.  Creating it, then appending input element..");
			const inputsDiv = document.createElement("div");
			inputsDiv.classList.add("inputs_divider_inputs");
			const inputsDivider_vrt = document.createElement("div");
			const inputsDivider_local = document.createElement("div");
			inputsDivider_local.className = "inputs_divider_local";
			inputsDivider_vrt.className = "inputs_divider_vrt";
			this.uiContainer = inputsDiv;
			// The _vrt divider is a visual element, not an organizational one.
			inputsDiv.appendChild(inputsDivider_local);
			this.element.appendChild(inputsDivider_vrt);
			this.element.appendChild(inputsDiv);
			const observer = new MutationObserver(() => {
				if (this.uiContainer && this.uiContainer.parentNode) {
					this.uiContainer.appendChild(inputInstance.element);
					observer.disconnect();
				}
			});
			observer.observe(document, { childList: true, subtree: true });
		}
		let groupInstance = window.root.groups.get(this.controls.GROUP);
		groupInstance.registerGroupInput(inputInstance);
		// Notify global listeners if this input is active
		if (window.root?.activeGroupInputsEmitter) {
			window.root.activeGroupInputsEmitter.emit(this.hashID);
		}
		// Force UI update for the host element
		if (this.element) {
			this.element.classList.add('host-updated');
			requestAnimationFrame(() => {
				this.element.classList.remove('host-updated');
			});
		}
	}
	createScreencastWidget() {
		console.log("Registering screencasting widget for host", this.hashID);
		// create the element from its function and append to self
		let screencastWidget;
		screencastWidget=(generateScreencastWidget(this));
		// ensure we have a direct reference to the widget in the host instance
		this.screencastWidget = screencastWidget;
		this.element.appendChild(screencastWidget);
		if (this.element) {
			this.element.classList.add('host-updated');
			requestAnimationFrame(() => {
				this.element.classList.remove('host-updated');
			});
		}
	}
	unregisterInput(inputInstance) {
		// unregisters the input from the host and deletes its DOM element
		const inputElement = inputInstance.element;
		let group = window.root.groups.get(this.controls.GROUP);
		if (group) {
			group.unregisterInput(inputInstance.hashID);
		}
		// Remove from global inputs map
		window.root.inputs.delete(inputInstance.hashID);
		// Remove the DOM element if it exists
		if (inputElement && inputElement.parentNode) {
			inputElement.remove();
		}
		// Remove from the host's inputs map
		this.inputs.delete(inputInstance.hashID);
		// Clear the element reference on the input instance
		inputInstance.element = null;
	}
	unregisterHost(){
		// destroy the host object instance and all DOM elements
	}
}

class Input {
	constructor(data) {
		this.hashID = data.hashID;
		// this.dataString = data.keyFull; // keyFull
		this.labelText = data.labelText;
		this.type = data.type;
		this.subType = data.subType || "net";
		this.hostHash = data.hostHash;
		this.active = data.isActive;
		this.direct = data.directMode;
		// Add update tracking
		this.lastUpdate = null; // TODO - should be timestamp
	}
}

class EventEmitter {
	constructor() {
		this.listeners = new Map();
	}
	on(event, callback) {
		if (!this.listeners.has(event)) {
			this.listeners.set(event, []);
		}
		this.listeners.get(event).push(callback);
	}
	off(event, callback) {
		if (this.listeners.has(event)) {
			const callbacks = this.listeners.get(event);
			const index = callbacks.indexOf(callback);
			if (index !== -1) {
				callbacks.splice(index, 1);
			}
			if (callbacks.length === 0) {
				this.listeners.delete(event);
			}
		}
	}
	emit(event, data) {
		if (this.listeners.has(event)) {
			this.listeners.get(event).forEach(callback => callback(data));
		}
	}
	subscribe(callback) {
		// Subscribe to all events (event '*' or no event)
		this.on('*', callback);
		return () => this.off('*', callback);
	}
}

class DragDropManager {
	constructor() {
		this.dragInstance = null;
		this.root = window.root;
		// Bind methods to preserve 'this' context
		this.handleDragStart = this.handleDragStart.bind(this);
		this.handleDragEnd = this.handleDragEnd.bind(this);
		this.handleDragOver = this.handleDragOver.bind(this);
		this.handleDrop = this.handleDrop.bind(this);
	}
	getInstanceFromElement(element) {
		const type = element.dataset?.type;
		const hashID = element.dataset?.hash;
		if (!type || !hashID) return null;
		let instance = null;
		switch (type) {
			case 'group': instance = this.root.groups?.get(hashID) || null; break;
			case 'host': instance = this.root.hosts?.get(hashID) || null; break;
			default: return null;
		}
		if (instance) {
			const containerElement = element.closest(`[data-hash="${hashID}"][data-type="${type}"]`);
			if (containerElement === instance.element) {
				return instance;
			}
		}
		return instance;
	}
	handleDragStart(event) {
		const element = event.target.closest('[data-hash]');
		if (!element) return;
		const dragInstance = this.getInstanceFromElement(element);
		if (!dragInstance || (dragInstance.type !== "group" && dragInstance.type !== "host")) {
			return;
		}
		this.dragInstance = dragInstance;
		event.dataTransfer.setData('text/hash-id', dragInstance.hashID);
		event.dataTransfer.setData('text/object-type', dragInstance.type);
		event.dataTransfer.effectAllowed = 'move';
		if (dragInstance.element) {
			dragInstance.element.classList.add('dragging');
		}
	}
	handleDragEnd() {
		if (this.dragInstance && this.dragInstance.element) {
			this.dragInstance.element.classList.remove('dragging');
		}
		this.dragInstance = null;
	}
	handleDragOver(event) {
		event.preventDefault();
		event.dataTransfer.dropEffect = 'move';
	}
	handleDrop(event) {
		event.preventDefault();
		const draggedHashID = event.dataTransfer.getData('text/hash-id');
		const draggedObjectType = event.dataTransfer.getData('text/object-type');
		const draggedInstance = draggedObjectType === 'group'
			? this.root.groups.get(draggedHashID)
			: this.root.hosts.get(draggedHashID);
		if (!draggedInstance) return;
		const targetElement = event.target.closest('[data-hash]');
		if (!targetElement) return;
		const targetInstance = this.getInstanceFromElement(targetElement);
		if (!targetInstance) return;
		const draggedHash = draggedInstance.hashID;
		const targetHash = targetInstance.hashID;
		const draggedType = draggedInstance.type;
		const targetType = targetInstance.type;
		if (draggedType === 'group' && targetType === 'group' && targetHash !== draggedHash) {
			const sourceHashValue = `${targetHash}:${targetInstance.controls.sourceHash || '1'}`;
			void window.root.controlRequestManager.send({ operation: "GROUPCONTROL", parentHash: draggedHash, parentType: "group", controlKey: "chainedToGroup", controlValue: targetHash, toggleOn: false });
			void window.root.controlRequestManager.send({ operation: "GROUPCONTROL", parentHash: draggedHash, parentType: "group", controlKey: "changeGroupSource", controlValue: sourceHashValue, toggleOn: false });
			draggedInstance.controls.chainedToGroup = targetHash;
			draggedInstance.sourceHash = sourceHashValue;
		} else if (draggedType === 'host' && targetType === 'group') {
			if (draggedInstance.controls.type !== "svr") {
				void window.root.controlRequestManager.send({
					operation: "HOSTCONTROL",
					parentHash: draggedHash,
					parentType: "host",
					controlKey: "changeGroup",
					controlValue: targetHash,
					toggleOn: false
				});
			}
		}
	}
}

class ControlRequestManager {
	async send(options) {
		const payload = {
			hash: options.parentHash,
			request: options.operation,
			data: options.extraData || null,
			type: options.parentType.toUpperCase(),
			parentHash: options.parentHash
		};
		if (options.operation === 'GROUPCONTROL' || options.operation === 'HOSTCONTROL' || options.operation === 'GLOBALSCONTROL') {
			payload.data = options.toggleOn
				? `${options.controlKey}:${options.controlValue}:TOGGLE`
				: `${options.controlKey}:${options.controlValue}`;
		}
		try {
			const response = await fetch('set_control.php', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(payload)
			});
			const contentType = response.headers.get('content-type');
			if (!contentType || !contentType.includes('json')) {
				const text = await response.text();
				console.warn('Non-JSON response received:', text);
			}
			if (!response.ok) {
				const errorText = await response.text();
				console.error('Control operation failed:', errorText);
			}
			return await response.json();
		} catch (error) {
			console.log('ERROR: ', error);
			return null;
		}
	}
}

class SSEManager {
	constructor(url) {
		this.url = url;
		this.eventSource = null;
		this.listeners = new Map(); // event -> [callbacks]
		this.lastHeartbeatId = -1;
		this.missedHeartbeats = 0;
		this.reconnectAttempts = 0;
		this.maxReconnectDelay = 30000;
		this.lastStatus = null
		this.heartbeatMonitor = null;
	}
	connect() {
		// Prevent stacking connections
		if (this.eventSource) {
			console.warn('SSE already connected, closing old connection');
			this.close();
		}
		this.eventSource = new EventSource(this.url);
		// Centralize all event binding here
		this.setupListeners();
		// Start the heartbeat monitor immediately
		this.startHeartbeatMonitor();
	}
	setupListeners() {
		const es = this.eventSource;
		// Connection state changes
		es.onopen = () => {
			console.log('SSE connected');
			this.reconnectAttempts = 0;
			this.updateConnectionStatus('connected');
		};
		es.onerror = () => {
			if (es.readyState === EventSource.CLOSED) {
				this.updateConnectionStatus('disconnected');
				this.scheduleReconnect();
			} else {
				// transient error during active connection — ignore
			}
		};
		// Named events override onmessage
		['heartbeat', 'etcd_update', 'error'].forEach(eventName => {
			es.addEventListener(eventName, (event) => {
				try {
					const data = JSON.parse(event.data);
					this.handleData(data);
				} catch (e) {
					console.warn(`Failed to parse ${eventName}:`, e);
				}
			});
		});
		// Fallback for unnamed events
		es.onmessage = (event) => {
			try {
				const data = JSON.parse(event.data);
				this.handleData(data);
			} catch (e) {
				console.warn('Failed to parse message:', e);
			}
		};
	}
	handleData(data) {
		// Defensive check: Ensure data is a valid object before processing
		if (!data || typeof data !== 'object') return;
		// Heartbeat handling with ID tracking
		if (data.time && data['server_time']) {
			this.trackHeartbeat();
			return;
		}
		// Status messages
		if (data.status) {
			this.updateConnectionStatus(data.status);
			return;
		}
		// Error messages
		if (data.error) {
			console.warn('SSE error:', data.error);
			return;
		}
		// Event arrays get routed to handlers
		if (Array.isArray(data)) {
			this.handleEtcdEvents(data);
			updateLastUpdateTime();
		}
	}
	trackHeartbeat() {
		// Reset missed count on successful heartbeat
		this.missedHeartbeats = 0;
	}
	scheduleReconnect() {
		if (this.heartbeatMonitor) clearInterval(this.heartbeatMonitor);

		const delay = Math.min(
			1000 * Math.pow(2, this.reconnectAttempts),
			this.maxReconnectDelay
		);

		console.log(`SSE reconnecting in ${delay}ms (attempt ${this.reconnectAttempts + 1})`);

		setTimeout(() => {
			this.reconnectAttempts++;
			this.connect();
		}, delay);
	}
	close() {
		if (this.eventSource) {
			this.eventSource.close();
			this.eventSource = null;
		}
		if (this.heartbeatMonitor) {
			clearInterval(this.heartbeatMonitor);
			this.heartbeatMonitor = null;
		}
		this.listeners.clear();
	}
	startHeartbeatMonitor() {
		if (this.heartbeatMonitor) clearInterval(this.heartbeatMonitor);

		this.heartbeatMonitor = setInterval(() => {
			if (this.missedHeartbeats >= 3) {
				console.warn('Missed 3 heartbeats, reloading');
				location.reload();
			}
		}, 1000);
	}
	updateConnectionStatus(status) {
		if (this.lastStatus === status) return; // skip duplicate calls
		this.lastStatus = status;
		const statusEl = document.getElementById('connection-status');
		if (statusEl) {
			statusEl.textContent = status;
			statusEl.className = `status-${status}`;
		}
	}
	// Helper to route events to the existing handlers in your file
	handleEtcdEvents(events) {
		// 2. Safety check: Ensure we are iterating an array
		if (!Array.isArray(events)) {
			console.warn('SSEManager: Received non-array event data', events);
			return;
		}
		events.forEach(event => {
			try {
				const eventData = parseEventToDataObject(event);
				if (!eventData) return;

				switch (eventData.section) {
					case 'GROUPS':
						handleGroupEvents(eventData);
						break;
					case 'HOSTS':
						void handleHostEvents(eventData);
						break;
					case 'INPUTS':
						void handleInputEvents(eventData);
						break;
					case 'GLOBALS':
						handleGlobalsEvents(eventData);
						break;
				}
			} catch (error) {
				// 3. CRITICAL: Isolate errors so one bad event doesn't kill the stream
				console.error(`SSEManager: Error processing event ${event.key}:`, error);
			}
		});
	}
}


//
//
// Initial fetch calls
//
//


async function setupUIAfterAjax() {
	// Generates UI elements based off previously populated data in fetchData
    const hostControlDiv = document.getElementById('HostControlDiv');
    let hostControlHeaderDiv = document.createElement("div");
    let hostControlLabelDiv = document.createElement("div");
    let hostControlControlDiv = document.createElement("div");
    hostControlHeaderDiv.appendChild(hostControlControlDiv);
    hostControlHeaderDiv.appendChild(hostControlLabelDiv);
    hostControlDiv.appendChild(hostControlHeaderDiv);
    hostControlHeaderDiv.className = 'group_header_div';
    hostControlLabelDiv.className = 'group_control_div';
    hostControlControlDiv.className = 'toggle_control_div';
    let headerSpan = document.createElement("span");
    headerSpan.classList.add("label");
    hostControlHeaderDiv.appendChild(headerSpan);

	// Create global options and groups first
	// console.log("First group type:", typeof groupsData[0], "Is instance?:", groupsData[0] instanceof Group);
	console.debug("Data: ", window.root);

	// Generate a toggle button for simple mode
	const container = document.createElement("div");
	let toggleValue = window.root.globals.lowInformationMode;
	if (typeof toggleValue !== 'boolean') {
		toggleValue = toggleValue === 1 || toggleValue === '1' || toggleValue === true;
		window.root.globals.lowInformationMode = toggleValue;
	}
	const isChecked = !!toggleValue;
	console.log(`Generating mode toggle with value ${isChecked} (type: ${typeof toggleValue})`);
	const toggleHTML = `
	<label class="toggle">
		<input type="checkbox" 
			title="Switch between UI modes Adv/Simple"
			id="lowInformationMode_toggle_checkbox" 
			class="toggle-checkbox"
			${isChecked ? 'checked' : ''}
			data-globals="true"
		>
		<span class="toggleSwitch"></span>
		<span class="toggle-label">Switch UI Mode (Advanced/Normal)</span>
	</label>
	`;
	const temp = document.createElement("div");
	temp.innerHTML = toggleHTML.trim();
	const labelElement = temp.firstChild;
	container.appendChild(labelElement);
	const toggleElement = labelElement.querySelector('.toggle-checkbox');
	if (toggleElement) {
		toggleElement.addEventListener('change', function () {
			const controlValue = this.checked ? "1" : "0";
			console.log(`Toggle changed to: ${controlValue} (checked: ${this.checked})`);
			// Store the desired state before reload
			window.root.globals.pendingModeChange = controlValue;
			window.root.controlRequestManager.send({
				operation: "GLOBALSCONTROL",
				parentHash: "0",
				parentType: "GLOBALS",
				controlKey: "lowInformationMode",
				controlValue: controlValue,
				toggleOn: true
			}).then(() => {
				// Small delay to ensure backend receives the request
				setTimeout(() => {
					window.location.reload();
				}, 500);
			}).catch(error => {
				console.error("Request failed, but reloading anyway", error);
				window.location.reload();
			});
		});
	}
	hostControlControlDiv.appendChild(container);
	hostControlDiv.category = "GLOBALS";
	let globalsControlsDiv = document.createElement("Div");
	globalsControlsDiv.classList.add('globals_controls');

	// Group creation button
	if (toggleValue === false) {
		const groupsButton = createUnifiedButton({
			parentItem: hostControlDiv,
			parentHash: "0",
			groupHash: "0",
			title: "Create a new group object", // the button's hover tooltip
			dataLabel: "Create New Group", // the button's text on the UI
			operation: "createGroup", // the kind of operation we are performing
			value: "PLEASE", // the value we parse (in this case it's only the single value)
			buttonCategory: "GROUP" // This is the initial type switch for PHP to process.
		})
		globalsControlsDiv.appendChild(groupsButton);
	}
	// Soft Reset (GLOBAL CONTROL)
	if (toggleValue === false) {
		const softResetButton = createUnifiedButton({
			parentItem: hostControlDiv,
			parentHash: "0",
			groupHash: "0",
			title: "Toggle soft reset for all tasks on every client in the system",
			dataLabel: "Soft Reset",
			operation: "GLOBALSCONTROL",
			control: "softReset",
			value: "0",
			buttonCategory: "GLOBALS",
			toggleOn: true
		});
		softResetButton.dataset.toggleTextOn = "Soft Reset ON";
		softResetButton.dataset.toggleTextOff = "Soft Reset OFF";
		globalsControlsDiv.appendChild(softResetButton);
	}
	// Hard Reset (GLOBAL CONTROL)
	if (toggleValue === false) {
		const hardResetButton = createUnifiedButton({
			parentItem: hostControlDiv,
			parentHash: "0",
			groupHash: "0",
			title: "Hard resets the system. Allow ~3 minutes.",
			dataLabel: "Hard Reset",
			operation: "GLOBALSCONTROL",
			control: "hardReset",
			value: "0",
			buttonCategory: "GLOBALS",
			toggleOn: true
		});
		hardResetButton.dataset.toggleTextOn = "Hard Reset ON";
		hardResetButton.dataset.toggleTextOff = "Hard Reset OFF";
		globalsControlsDiv.appendChild(hardResetButton);
	}
	hostControlDiv.appendChild(globalsControlsDiv);
	const groupPromises = [];
	const hostPromises = [];
	const inputPromises = [];
	for (const group of window.root.groups.values()) {
		// console.log("Group UI setup:", group);
		if (group.hashID !== null) {
			// Never create group objects with no hashID.
			groupPromises.push(createGroupElement(group));
		}
	}
	await Promise.all(groupPromises);
	for (const group of window.root.groups.values()) {
		// Find all hosts belonging to this group
		for (const host of window.root.hosts.values()) {
			if (host.controls.GROUP === group.hashID) {
				hostPromises.push(createHostElement(host));
			}
		}
	}
	await Promise.all(hostPromises);
	for (const input of window.root.inputs.values()) {
		const inputParentHostInstance = window.root.hosts.get(input.hostHash);
		if (inputParentHostInstance) {
			inputPromises.push(inputParentHostInstance.registerHostInput(input));
		} else {
			console.warn(`No host found for input ${input.hashID}`);
		}
	}
	await Promise.all(inputPromises);
	await new Promise(resolve => requestAnimationFrame(resolve));
	for (const group of window.root.groups.values()) {
		group.updateActiveState();
	}
    console.log("UI setup completed");
}

function fetchData() {
	return fetch("/get_keys.php", {
		method: "POST",
		headers: {"Content-Type": "application/json"},
	}).then(response => {
		if (!response.ok) throw new Error('Network response was not ok');
		return response.json();
	}).then(data => {
		const result = [];
		// Handle globals
		if (data.globals) {
			// console.log(`Globals:`, data.globals);
			const rawLowInfoMode = data.globals?.['CONTROLS']?.lowInformationMode;
			const lowInfoModeBoolean = rawLowInfoMode === 1 || rawLowInfoMode === '1' || rawLowInfoMode === true || rawLowInfoMode === 'true';
			const globalData = {
				lowInformationMode: lowInfoModeBoolean,
				type: "global"
			};
			window.root.globals.lowInformationMode = lowInfoModeBoolean;
			result.push(globalData);
			const codecs = [];
			for (const [name, command] of Object.entries(data.globals['CODECS'])) {
				codecs.push({
					name: name,
					command: command
				});
			}
			window.root.codecs = codecs;
		}
		// Handle groups
		if (data.groups && Array.isArray(data.groups)) {
			data.groups.forEach(group => {
				const groupData = {
					hashID: group.hashID,
					label: group.controls.label || "UNKNOWN LABEL",
					audioStatus: group.controls.audioStatus || 0,
					blankStatus: group.controls.blankStatus || 0,
					bannerStatus: group.controls.bannerStatus || 0,
					bannerContent: group.controls.bannerContent || "DEFAULT",
					livestreamStatus: group.controls.livestreamStatus || 0,
					livestreamURL: group.controls.livestreamURL || null,
					livestreamKey: group.controls.livestreamKey || null,
					persistInput: group.controls.persistInput || 0,
					rebootStatus: group.controls.rebootStatus || 0,
					resetStatus: group.controls.resetStatus || 0,
					revealStatus: group.controls.revealStatus || 0,
					swatchValue: group.controls.swatchValue || "#0f2b39",
					sourceHash: group.controls.sourceHash || "",
					activeCodec: group.controls.activeCodec || "",
					isPrimary: group.controls.isPrimary || false,
					chainedToGroup: group.controls.chainedToGroup || null,
					type: "group",
					controls: group.controls || {}
				};
				console.log(`Creating class instance for group hash: ${group.hashID}`);
				// console.log(`Group data before class wrapping:`, groupData);
				// console.log(`Group instance after class wrapping:`, new Group(groupData));
				// console.log(`Is instance?:`, new Group(groupData) instanceof Group);
				const groupInstance = new Group(groupData);
				result.push(groupInstance);
				window.root.groups.set(group.hashID, groupInstance);
			});
		}
		// Handle hosts
		if (data.hosts && Array.isArray(data.hosts)) {
			data.hosts.forEach(host => {
				const hostData = {
					hashID: host.hashID,
					hostName: host.controls.label || host.key,
					ipAddress: host.hostIP || "ERROR",
					key: host.key,
					hostType: host.hostType,
					type: host.type,
					labelText: host.controls.label,
					parentGroup: host.controls.GROUP || 0,
					group: host.controls.GROUP || null,
					sourceFunction: 'fetchData',
					controls: {
						label: host.controls?.label || "UNKNOWN",
						blankStatus: host.controls?.blankStatus || "0",
						rebootStatus: host.controls?.rebootStatus || "0",
						resetStatus: host.controls?.resetStatus || "0",
						revealStatus: host.controls?.revealStatus || "0",
						healthStatus: host.controls?.healthStatus || "OK",
						GROUP: host.controls?.GROUP || null,
						directMode: host.controls?.directMode ?? "1",
						UIEnable: host.controls?.UIEnable ?? "0",
						screencastCapable: host.controls?.screencastCapable ?? "0",
						promote: host.controls?.promote ?? "0"
					}
				};
				console.log(`Creating class instance for host hash: ${host.hashID}`);
				const hostInstance = new Host(hostData);
				result.push(hostInstance);
				window.root.hosts.set(host.hashID, hostInstance);
				// console.debug("Host Instance: ", hostInstance);
				// Inputs are now also class instances
				if (host.inputs && Array.isArray(host.inputs)) {
					host.inputs.forEach(input => {
						const inputData = {
							hashID: input.hashID,
							keyFull: input.keyFull,
							labelText: input.labelText,
							type: "input",
							subType: input.subType,
							hostHash: input.parentHashID,
							active: input.isActive || false,
							direct: input.directMode ?? 1 // used to toggle ingestion into UltraGrid or for clients to subscribe direct
						};
						console.log(`Creating class instance for input hash: ${input.hashID}`);
						const inputInstance = new Input(inputData)
						result.push(inputInstance);
						window.root.inputs.set(input.hashID, inputInstance);
						hostInstance.inputs.set(inputInstance.hashID, inputInstance);
					});
				}
			});
		}
		return result;
	}).catch(error => {
		console.error("Fetch error: ", error);
		return [];
	});
}


//
//
// Group elements code
//
//


function createToggleBox(parentInstance, controlKey, controlLabel) {
	// General function to create a toggle box object
	const container = document.createElement("div");
	// Perform checks on the parentElement dataset
	const toggleValue = parentInstance.controls?.[controlKey] ?? false;
	const isChecked = (toggleValue === 1 || toggleValue === true || toggleValue === '1');
	const toggleHTML = `
		<label class="toggle">
			<input type="checkbox" 
				title="Enable function: ${controlLabel}"
				id="${controlKey}_toggle_checkbox" 
				class="toggle-checkbox"
				${isChecked ? 'checked' : ''}
			>
			<span class="toggleSwitch"></span>
			<span class="toggle-label">${controlLabel}</span>
		</label>
	`;
	const temp = document.createElement("div");
	temp.innerHTML = toggleHTML.trim();
	const labelElement = temp.firstChild;
	container.appendChild(labelElement);
	const toggleElement = labelElement.querySelector('.toggle-checkbox');
	let operationType = "?";
	if (toggleElement) {
		toggleElement.addEventListener('change', function () {
			if (parentInstance instanceof Group) {
				operationType = "GROUPCONTROL"
			} else if (parentInstance.type === "host") {
				operationType = "HOSTCONTROL";
			}
			const controlValue = this.checked ? "1" : "0";
			void window.root.controlRequestManager.send({
				operation: operationType,
				parentHash: parentInstance.hashID,
				controlKey: controlKey,
				controlValue: controlValue,
				parentType: parentInstance.type,
				toggleOn: controlValue
			});
		});
	}
	return container;
}

function createCodecDropdown(groupItem) {
	let select = document.createElement("select");
	select.classList.add("source-dropdown");
	select.id = "codecSelector_" + groupItem.hashID;
	select.title = "Select available codec ";
	select.addEventListener("focus", () => select.classList.add("open"));
	return select;
}

function refreshCodecDropdown(select, groupItem) {
	// Ensure root object exists and has codecs
	if (!window.root || !window.root.codecs) {
		console.warn("Root object or codecs not available");
		return;
	}
	const availableCodecs = window.root.codecs; // This is an array of codec objects
	const activeCodec = groupItem.controls.activeCodec;
	const newSelect = document.createElement("select");
	newSelect.classList.add("source-dropdown");
	newSelect.id = "codecSelector_" + groupItem.hashID;
	newSelect.title = "Select available codec ";
	newSelect.addEventListener("focus", () => newSelect.classList.add("open"));
	const oldSelect = select;
	const options = Array.from(oldSelect.options).map(opt => {
		const newOpt = document.createElement("option");
		newOpt.text = opt.text;
		newOpt.value = opt.value;
		newOpt.className = opt.className;
		return newOpt;
	});
	options.forEach(opt => newSelect.appendChild(opt));
	if (oldSelect.parentNode) {
		oldSelect.parentNode.replaceChild(newSelect, oldSelect);
	} else {
		document.body.appendChild(newSelect); // This should not happen, it's just for safety
	}
	// Add the available codecs
	if (availableCodecs.length > 0) {
		const thisGroupOptgroup = document.createElement("optgroup");
		thisGroupOptgroup.label = "Available Codecs";
		// Sort by whether they match the active codec
		const sortedCodecs = [
			...availableCodecs.filter(codec => codec.name === activeCodec),
			...availableCodecs.filter(codec => codec.name !== activeCodec)
		];
		sortedCodecs.forEach(codec => {
			const option = document.createElement("option");
			option.text = (codec.name === activeCodec ? '● ' : '') + codec.name;
			option.value = codec.name; // Set the value to the codec name
			option.title = codec.description;
			option.className = "dropdown-content-item";
			if (codec.name === activeCodec) {
				option.selected = true;
			}
			thisGroupOptgroup.appendChild(option);
		});
		newSelect.appendChild(thisGroupOptgroup);
	}
	document.addEventListener('codecDropdownRefresh', () => refreshCodecDropdown(newSelect, groupItem));
	newSelect.addEventListener("change", () => {
		const selectedCodec = newSelect.value;
		console.log("Codec changed to:", selectedCodec);
		groupItem.activeCodec = selectedCodec; // Update the group item's activeCodec
		let hashID = groupItem.hashID;
		void window.root.controlRequestManager.send({
			operation: "GROUPCONTROL",
			parentHash: hashID,
			controlKey: "changeGroupCodec",
			controlValue: selectedCodec,
			parentType: "group",
			toggleOn: false
		});
		document.dispatchEvent(new Event('codecDropdownRefresh'));
	});
}

async function createSourceDropdown(groupItem) {
	const groupHash = groupItem.hashID;
	const select = document.createElement("select");
	select.classList.add("source-dropdown");
	select.id = "sourceSelector_" + groupHash;
	select.title = "Select video source for this group (can be an input, or another group — in which case, it will be the active source in that group.)";
	// Track refresh state
	select.dataset.isRefreshing = 'false';
	select.dataset.lastSourceHash = '';
	// Lifecycle handlers
	const handleFocus = () => select.classList.add("open");
	const handleBlur = () => select.classList.remove("open");
	const handleChange = async () => {
		// Activates an input when it's selected from the source dropdown
		groupItem.handleSourceChange(select.value);
	};
	select.addEventListener("focus", handleFocus);
	select.addEventListener("blur", handleBlur);
	select.addEventListener("change", handleChange);
	document.addEventListener('sourceDropdownRefresh', handleSourceDropdownRefresh);
	// Initial build (reuse the wired-up select so listeners survive the populate pass)
	groupItem.sourceDropdownElement = select;
	refreshDropdown(groupItem);
	// Subscribe to registry changes (handled by global emitter)
	const unsubscribe = window.root.activeGroupInputsEmitter.subscribe(changedHash => {
		if (changedHash === '*' || changedHash === groupHash) {
			refreshDropdown(groupItem);
		}
	});
	// Cleanup helper
	select.cleanup = () => {
		select.removeEventListener("focus", handleFocus);
		select.removeEventListener("blur", handleBlur);
		select.removeEventListener("change", handleChange);
		unsubscribe();
	};
	return select;
}

function handleSourceDropdownRefresh(event) {
	const groupInstance = event?.detail?.detail || event?.detail || event;
	if (!(groupInstance instanceof Group)) {
		console.warn(`handleSourceDropdownRefresh: Expected Group instance, got ${groupInstance?.constructor?.name || typeof groupInstance}`);
		return;
	}
	refreshDropdown(groupInstance);
}

function refreshDropdown(groupInstance) {
	// Ensure we're working with a Group class instance
	if (!(groupInstance instanceof Group)) {
		console.warn(`refreshDropdown: Expected Group instance, got ${groupInstance?.constructor?.name || typeof groupInstance}`);
		return;
	}
	let select = groupInstance.sourceDropdownElement;
	if (!select) {
		// CREATE mode: build new dropdown if element doesn't exist yet
		const newSelect = buildDropdownOptions(groupInstance);
		if (!newSelect || newSelect.tagName !== 'SELECT') {
			console.warn(`refreshDropdown: buildDropdownOptions returned ${newSelect?.tagName || typeof newSelect} instead of <select>`);
			return;
		}
		groupInstance.sourceDropdownElement = newSelect;
		newSelect.dataset.isRefreshing = 'false';
		newSelect.dataset.lastSourceHash = newSelect.value;
		console.log(`refreshDropdown: Created new source dropdown for group ${groupInstance.hashID}`);
		select = newSelect;
	}
	if (select.dataset.isRefreshing === 'true') return;
	select.dataset.isRefreshing = 'true';
	try {
		const newSelect = buildDropdownOptions(groupInstance);
		if (!newSelect || newSelect.tagName !== 'SELECT') {
			console.warn(`refreshDropdown: buildDropdownOptions returned ${newSelect?.tagName || typeof newSelect} instead of <select>`);
			return;
		}
		// Preserve existing event listeners by replacing content while keeping the same element reference
		select.innerHTML = newSelect.innerHTML;
		select.value = newSelect.value;
		select.dataset.lastSourceHash = select.value;
		// Notify all groups about the refresh
		if (window.root && window.root.activeGroupInputsEmitter) {
			window.root.activeGroupInputsEmitter.emit('*');
		}
		// console.log(`refreshDropdown: Refreshed source dropdown for group ${groupInstance.hashID}, active=${select.value}`);
	} finally {
		select.dataset.isRefreshing = 'false';
	}
	// console.log("Refreshed sourceDropDown for group: ", groupInstance.hashID);
}

function buildDropdownOptions(groupInstance) {
	const select = document.createElement("select");
	select.classList.add("source-dropdown");
	select.id = `sourceSelector_${groupInstance.hashID}`;
	select.title = "Select video source for this group (can be an input, or another group — in which case, it will be the active source in that group.)";
	select.addEventListener("focus", () => select.classList.add("open"));
	const externalPrefix = groupInstance.isChained() ? '🔗 ' : '';
	// 1: Local inputs (from Group class instance)
	// console.log(`buildDropdownOptions: Processing group ${groupHash} (${groupItem.label})`);
	const localInputs = Array.from(groupInstance.inputs.values()).map(entry => {
		const inputHash = entry.hashID;
		const inputLabel = entry.labelText || entry.inputLabel;
		return { inputHash, inputLabel };
	});
	if (localInputs.length > 0) {
		// this should always >= 3 basic inputs + dynamic inputs
		const optgroup = document.createElement("optgroup");
		optgroup.label = "Local Inputs:"
		// console.log(`buildDropdownOptions: Adding ${localInputs.length} local inputs to optgroup "Local Inputs"`);
		const localHeader = document.createElement("localHeader");
		localHeader.text = optgroup.label;
		localHeader.className =  "dropdown-content-header";
		optgroup.appendChild(localHeader);
		for (const input of localInputs) {
			const isActive = input.inputHash === groupInstance.controls.sourceHash;
			const option = document.createElement("option");
			const prefix = (isActive && externalPrefix === '') ? '● ' : '';
			option.value = groupInstance.hashID + ':' + input.inputHash;
			option.className = "dropdown-content-item";
			option.text = externalPrefix + prefix + input.inputLabel;
			option.className = "dropdown-content-item";
			if (isActive) option.selected = true;
			optgroup.appendChild(option);
			// console.debug(`buildDropdownOptions: Added local input option ${input.inputHash} (active=${isActive})`);
		}
		select.appendChild(optgroup);
		// console.log(`buildDropdownOptions: Appended "Group Inputs" optgroup to select#${select.id}`);
	}
	// 2: Sources from external groups
	const otherGroupInputs = Array.from(window.root.groups.entries())
		.filter(([hash]) => hash !== groupInstance.hashID)
		.map(([hash, group]) => ({
			groupHash: hash,
			groupLabel: group.controls.label,
			inputHash: group.controls.sourceHash,
			inputLabel: group.inputs.get(group.controls.sourceHash)?.labelText || 'NULL'
		}))
		.filter(entry => entry.inputLabel && entry.inputLabel !== 'NULL'); // Filter out entries with null/empty labels to avoid potential loops
	// console.debug("Other group inputs:", otherGroupInputs);
	if (otherGroupInputs.length > 0) {
		const optgroup = document.createElement("optgroup");
		const extHeader = document.createElement("extHeader");
		const isChained = groupInstance.controls.chainedToGroup; // returns hash value of the leader group, or null
		// we may want a recurse function here to follow chaining leaders and see if we appear upstream.  if we do, we set isChained = null
		optgroup.label = "Other Chainable Inputs: "
		extHeader.text = optgroup.label;
		extHeader.className =  "dropdown-content-header";
		optgroup.appendChild(extHeader);
		for (const entry of otherGroupInputs) {
			const option = document.createElement("option");
			option.value = entry.groupHash + ':' + entry.inputHash;
			option.text = externalPrefix + entry.groupLabel + " → " + entry.inputLabel;
			option.className = "dropdown-content-item";
			const externalGroupInstance = window.root.groups.get(entry.groupHash);
			if (externalGroupInstance) {
				const swatch = externalGroupInstance.controls.swatchValue || "#0f2b39";
				if (swatch && /^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$/.test(swatch)) {
					option.style.setProperty('--swatch-bg', swatch);
					option.style.backgroundColor = swatch;
				}
			}
			if (isChained === entry.groupHash) {
				option.selected = true;
			}
			option.title = `Chained to group: ${entry.groupLabel} — will follow all input changes`;
			// if we are chained to a group, set isActive for that group's active input.
			optgroup.appendChild(option);
		}
		select.appendChild(optgroup);
	}
	// console.log(`buildDropdownOptions: Completed dropdown for group ${groupHash}`);
	return select;
}


//
//
// Group/Host Interaction
//
//

function setElementBackgroundColor(element, swatchValue) {
	element.style.backgroundColor = swatchValue;
}

function createColorSwatch(item, element) {
	const container = document.createElement('div');
	container.setAttribute('title', "Pick a UI color for the group (user preference)");
	const pickerText = document.createTextNode("    Group Color ")
	let colorValue = item.controls.swatchValue || "#0f2b39";
	// Validate colorValue to avoid invalid values
	if (!/^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$/.test(colorValue)) {
		colorValue = "#0f2b39";
	}
	// console.info("Item hash:" + item.hashID + " with color: " + colorValue);
	const swatch = document.createElement('div');
	const picker = document.createElement('input');
	picker.type = "color";
	picker.id = `swatch-group-${item.hashID}`;
	picker.value = colorValue;
	picker.style.display = 'flex';
	picker.style.width = '2.5em';
	picker.style.height = '100%';
	picker.classList.add("htmlColorPicker")
	swatch.appendChild(picker);
	swatch.className = 'color-swatch';
	swatch.style.backgroundColor = colorValue;
	swatch.style.marginRight = "2em";
	// Open color picker when swatch is clicked
	swatch.addEventListener('click', () => {
		picker.click();
	});
	// Update colorValue and submit on selection (when user confirms via color picker)
	picker.addEventListener('input', (e) => {
		colorValue = e.target.value;
		swatch.style.backgroundColor = colorValue; // Update visual color
		// Only submit after color is selected (input event triggers on confirmation)
		if (element) {
			setElementBackgroundColor(element, colorValue);
		}
		void window.root.controlRequestManager.send({
			operation: 'GROUPCONTROL',
			parentHash: item.hashID,
			parentType: item.type,
			controlKey: 'swatchValue',
			controlValue: colorValue,
			toggleOn: false
		}).catch(error => {
			console.error('Failed to update background color on server:', error);
		});
	});
	container.style.display = ("flex");
	container.style.width = ("100%");
	container.style.height = ("1em");
	container.style.margin = (".5em");
	container.style.gap = ("1.1em");
	container.appendChild(swatch);
	container.appendChild(pickerText);
	return container;
}


//
//
// Host-specific code
//
//


async function createHostElement(hostInstance) {
	// This function creates a new host UI element for each host instance
	// A host is contained in a div element, which is drag+droppable to group element
	const divEntry = document.createElement("div");
	divEntry.setAttribute("data-type", "host");
	divEntry.setAttribute("draggable", "true");
	divEntry.classList.add("host_divider");
	divEntry.id = `host-${hostInstance.hashID}`;
	divEntry.title = `Host IP Address: ${hostInstance.ipAddress}`;
	divEntry.setAttribute("data-hash", hostInstance.hashID);
	// Add drag events
	divEntry.addEventListener("dragstart", window.root.dragDropManager.handleDragStart);
	divEntry.addEventListener("dragend", window.root.dragDropManager.handleDragEnd);
	divEntry.addEventListener('dragover', window.root.dragDropManager.handleDragOver);
	divEntry.addEventListener('drop', window.root.dragDropManager.handleDrop);
	hostInstance.category = "HOST";
	// Add the host button set
	const hostButtons = hostInstance.createHostButtonSet();
	divEntry.appendChild(hostButtons);
	// Generate input buttons if any input instances were created attached to this host
	if (hostInstance.inputs && hostInstance.inputs.size > 0) {
		console.info("Generating input container for: ", hostInstance.controls.label);
		// Add a vertical divider
		const inputsDiv = document.createElement("div");
		inputsDiv.classList.add('inputs_divider_inputs');
		const inputsDivider_local = document.createElement("div");
		const inputsDivider_vrt = document.createElement("div");
		inputsDivider_local.className = 'inputs_divider_local';
		inputsDivider_vrt.className = 'inputs_divider_vrt';
		inputsDiv.appendChild(inputsDivider_local);
		hostInstance.uiContainer = inputsDiv;
		// The vertical divider is a visual element, not an organizational element
		divEntry.appendChild(inputsDivider_vrt);
		divEntry.appendChild(inputsDiv);
	}
	if (hostInstance.controls['enableScreenCast'] === "1") {
		// we generate the screencast widget
		hostInstance.createScreencastWidget();
	}
	const parentGroupHash = hostInstance.controls.GROUP;
	const groupInstance = window.root.groups.get(parentGroupHash);
	if (groupInstance.element) {
		groupInstance.element.appendChild(divEntry);
	} else {
			console.warn("No group element after creation attempt!");
	}
	hostInstance.element = divEntry;
	requestAnimationFrame(() => {
		divEntry.classList.remove('host-created');
	});
	// Also ensure inputs get proper visual update if they exist
	if (hostInstance.inputs && hostInstance.inputs.size > 0 && hostInstance.uiContainer) {
		hostInstance.uiContainer.classList.add('inputs-container-updated');
		requestAnimationFrame(() => {
			hostInstance.uiContainer.classList.remove('inputs-container-updated');
		});
	}
}

function generateScreencastWidget(hostInstance){
	// generates a screencast widget to handle status, authorization and activation of screencasting
	const divEntry = document.createElement("div");
	divEntry.setAttribute("data-type", "screencastwidget");
	divEntry.classList.add("screencast_divider");
	divEntry.id = `screencast-host-${hostInstance.hashID}`;
	divEntry.setAttribute("data-hash", hostInstance.hashID);
	divEntry.style.cursor = "default";
	divEntry.style.fontWeight = "normal";
	// Store element refs directly
	const labelSpan = document.createElement("span");
	labelSpan.className = "btn__label";
	labelSpan.title = "Awaiting Connection";
	const textSpan = document.createElement("span");
	textSpan.textContent = "Awaiting Connection";
	labelSpan.appendChild(textSpan);
	const innerSpan = document.createElement("span");
	innerSpan.className = "btn__inner";
	innerSpan.appendChild(labelSpan);
	const backgroundOuter = document.createElement("span");
	backgroundOuter.className = "btn__background";
	divEntry.appendChild(innerSpan);
	divEntry.appendChild(backgroundOuter);
	let widgetState = 0;
	// This is the device hostname+MAC in a single string
	let deviceName = hostInstance.controls['screencastRequest'] || "";
	function setState(label, cursor, bgColor) {
		textSpan.textContent = label;
		labelSpan.title = label;
		divEntry.style.cursor = cursor;
		divEntry.style.fontWeight = cursor === 'pointer' ? 'bold' : 'normal';
		if (bgColor) divEntry.style.backgroundColor = bgColor;
	}
	if (hostInstance.controls['screenActive'] === "1") {
		widgetState = 2;
		setState("Cancel", "pointer", "#c8e6c9");
	} else if (hostInstance.controls['screencastRequest']) {
		widgetState = 1;
		deviceName = hostInstance.controls['screencastRequest'];
		setState(`Auth: ${deviceName}`, "pointer", null);
	}
	function watchControlChanges() {
		const reqValue = hostInstance.controls['screencastRequest'];
		const reqIsPresent = reqValue != null && String(reqValue).trim() !== "";
		if (widgetState === 2 && !reqIsPresent) {
			widgetState = 0;
			deviceName = "";
			setState("Awaiting Connection", "default", null);
		} else if (hostInstance.controls['screenActive'] === "1" && widgetState !== 2) {
			widgetState = 2;
			setState("Cancel screencasting", "pointer", "#c8e6c9");
		}
	}
	// SSE handler that updates the control and triggers the widget's watch
	hostInstance.emitter.on('controlUpdate', (data) => {
		const { controlName, newValue } = data;
		if (controlName === 'screencastRequest' || controlName === 'screenActive') {
			hostInstance.controls[controlName] = newValue;
			if (controlName === 'screencastRequest') {
				const reqIsPresent = newValue != null && String(newValue).trim() !== "";
				if (widgetState === 0 && reqIsPresent) {
					widgetState = 1;
					deviceName = newValue;
					setState(`Auth: ${deviceName}`, "pointer", null);
				} else if (widgetState === 1 && !reqIsPresent) {
					widgetState = 0;
					setState("Awaiting Connection", "default", null);
				}
			}
			watchControlChanges();
		}
	});
	divEntry.addEventListener('click', function() {
		switch(widgetState) {
			case 0:
				textSpan.textContent = "IDLE";
				labelSpan.title = "Awaiting device connection to encoder..";
				// Note there is no click or control here
				// The widget is in a waiting state until a device attempts connection
				// the backend will send SSE notification that will cause the widget to mutate
				break;
			case 1:
				textSpan.textContent = `${hostInstance.controls['screencastRequest']}`;
				// the hover text should say "AUTHORIZE"
				labelSpan.title = "A device has connected, check hostname/MAC and click to authorize it";
				window.root.controlRequestManager.send({
					operation: "HOSTCONTROL",
					parentHash: hostInstance.hashID,
					parentType: "host",
					controlKey: "authorizeScreencast",
					controlValue: "1",
					toggleOn: false
				}).then(() => {
					widgetState = 2;
					setState("Cancel screencasting", "pointer", "#c8e6c9");
				}).catch(() => {
					textSpan.textContent = "Auth failed";
					labelSpan.title = "Auth failed";
					divEntry.style.backgroundColor = "#ffcdd2";
					setTimeout(() => {
						setState(`Auth: ${deviceName}`, "pointer", null);
					}, 2000);
				});
				break;
			case 2:
				textSpan.textContent = "STOP";
				labelSpan.title = "Stop screencasting immediately";
				window.root.controlRequestManager.send({
					operation: "HOSTCONTROL",
					parentHash: hostInstance.hashID,
					parentType: "host",
					controlKey: "enableScreenCast",
					controlValue: "0",
					toggleOn: false
				}).then(() => {
					widgetState = 0;
					setState("Awaiting Connection", "default", null);
				}).catch(() => {
					textSpan.textContent = "Stop failed";
					labelSpan.title = "Stop failed";
					setTimeout(() => {
						setState("Cancel screencasting", "pointer", "#c8e6c9");
					}, 2000);
				});
				break;
		}
	});
	return divEntry;
}

function createHealthIndicator(hostInstance) {
	// Generates a health indicator styled by CSS
	// console.log("Generating health indicator for host:", hostInstance.controls.label);
	const healthBox = document.createElement("div");
	healthBox.id = `health-${hostInstance.hashID}`;
	healthBox.className = "hostHealth_divider";
	// Map status strings to CSS numeric values and labels
	const statusConfig = {
		'OK': {
			value: '0',
			label: 'Healthy'
		},
		'WARN': {
			value: '6',
			label: 'Warning'
		},
		'ERR': {
			value: '5',
			label: 'Error'
		},
		'FTL': {
			value: '3',
			label: 'Fatal'
		},
		'UNR': {
			value: '4',
			label: 'Offline'
		},
		'DEAD': {
			value: '4',
			label: 'Offline'
		}
	};
	const status = hostInstance.controls.healthStatus || 'OK';
	// Extract the short status code by finding the first colon, space, or using the whole string if no separator
	const shortStatus = status.split(/[:\s]+/)[0] || status;
	const config = statusConfig[shortStatus] || statusConfig['OK'];
	healthBox.setAttribute("data-healthStatus", config.value);
	// Set title to include the full raw event value for more context
	healthBox.title = `Health Status: ${config.label} (Raw: ${escapeHTML(status)})`;
	healthBox.textContent = config.label;
	return healthBox;
}

function createENCNotifier(hostInstance) {
	const encNotifierDiv = document.createElement("div");
	encNotifierDiv.classList.add("enc-notifier");
	encNotifierDiv.title = "This host is operating as an encoder";
	const encText = document.createTextNode("ENC");
	encNotifierDiv.appendChild(encText);
	const encEnabledValue = hostInstance.controls.promote ?? 0;
	encNotifierDiv.setAttribute('data-active', String(encEnabledValue));
	if (encEnabledValue === "1" || encEnabledValue === 1) {
		const buttonsDiv = hostInstance.element?.querySelector('.host-buttons');
		if (buttonsDiv) {
			const existing = buttonsDiv.querySelector('.enc-notifier');
			if (existing) existing.remove();
			buttonsDiv.appendChild(encNotifierDiv);
			hostInstance.encNotifier = encNotifierDiv;
		}
	} else {
		hostInstance.encNotifier = encNotifierDiv;
	}
	if (hostInstance.emitter) {
		hostInstance.emitter.on('controlUpdate', (data) => {
			if (data.controlName === 'promote') {
				const newValue = data.newValue;
				const isEnabled = newValue === "1" || newValue === 1 || newValue === true;
				encNotifierDiv.setAttribute('data-active', String(newValue));
				if (isEnabled) {
					const buttonsDiv = hostInstance.element?.querySelector('.host-buttons');
					if (buttonsDiv) {
						const existing = buttonsDiv.querySelector('.enc-notifier');
						if (existing) existing.remove();
						buttonsDiv.appendChild(encNotifierDiv);
					}
				} else {
					if (encNotifierDiv.parentNode) {
						encNotifierDiv.remove();
					}
				}
			}
		});
	}
	return encNotifierDiv;
}

function createUINotifier(hostInstance) {
	// Create the UI notifier element
	const uiNotifierDiv = document.createElement("div");
	uiNotifierDiv.classList.add("ui-notifier");
	uiNotifierDiv.title = "This client has its UI enabled";
	const uiNotifierText = document.createTextNode("UI");
	uiNotifierDiv.appendChild(uiNotifierText);
	// Set initial state based on controls
	const uiEnabledValue = hostInstance.controls.UIEnable ?? 0;
	uiNotifierDiv.setAttribute('data-active', uiEnabledValue);
	// Only append to DOM if UI is enabled (value = 1)
	if (uiEnabledValue === 1) {
		const buttonsDiv = hostInstance.element?.querySelector('.host-buttons');
		if (buttonsDiv) {
			// Remove existing notifier if one exists
			const existingNotifier = buttonsDiv.querySelector('.ui-notifier');
			if (existingNotifier) existingNotifier.remove();
			buttonsDiv.appendChild(uiNotifierDiv);
			hostInstance.uiNotifier = uiNotifierDiv;
		}
	} else {
		// If UI is disabled (value = 0), don't append to DOM (invisible)
		hostInstance.uiNotifier = uiNotifierDiv;
	}
	// Subscribe to host emitter for real-time updates
	if (hostInstance.emitter) {
		hostInstance.emitter.on('controlUpdate', (data) => {
			if (data.controlName === 'UIEnable') {
				const newValue = data.newValue;
				const isEnabled = newValue === "1" || newValue === 1 || newValue === true;
				uiNotifierDiv.setAttribute('data-active', String(newValue));
				if (isEnabled) {
					const buttonsDiv = hostInstance.element?.querySelector('.host-buttons');
					if (buttonsDiv) {
						const existing = buttonsDiv.querySelector('.ui-notifier');
						if (existing) existing.remove();
						buttonsDiv.appendChild(uiNotifierDiv);
					}
				} else {
					if (uiNotifierDiv.parentNode) {
						uiNotifierDiv.remove();
					}
				}
			}
		});
	}
	return uiNotifierDiv;
}

function createNDINotifier(hostInstance) {
	const ndiNotifierDiv = document.createElement("div");
	ndiNotifierDiv.classList.add("ndi-notifier");
	ndiNotifierDiv.title = "This host is an NDI network device";
	const ndiText = document.createTextNode("NDI");
	ndiNotifierDiv.appendChild(ndiText);
	const ndiEnabledValue = hostInstance.type === "NDI" ? "1" : "0";
	ndiNotifierDiv.setAttribute('data-active', ndiEnabledValue);
	if (ndiEnabledValue === "1") {
		const buttonsDiv = hostInstance.element?.querySelector('.host-buttons');
		if (buttonsDiv) {
			const existing = buttonsDiv.querySelector('.ndi-notifier');
			if (existing) existing.remove();
			buttonsDiv.appendChild(ndiNotifierDiv);
			hostInstance.ndiNotifier = ndiNotifierDiv;
		}
	} else {
		hostInstance.ndiNotifier = ndiNotifierDiv;
	}
	return ndiNotifierDiv;
}

function createRTSPNotifier(hostInstance) {
	const rtspNotifierDiv = document.createElement("div");
	rtspNotifierDiv.classList.add("rtsp-notifier");
	rtspNotifierDiv.title = "This host is an RTSP network device";
	const rtspText = document.createTextNode("RTSP");
	rtspNotifierDiv.appendChild(rtspText);
	const rtspEnabledValue = hostInstance.type === "RTSP" ? "1" : "0";
	rtspNotifierDiv.setAttribute('data-active', rtspEnabledValue);
	if (rtspEnabledValue === "1") {
		const buttonsDiv = hostInstance.element?.querySelector('.host-buttons');
		if (buttonsDiv) {
			const existing = buttonsDiv.querySelector('.rtsp-notifier');
			if (existing) existing.remove();
			buttonsDiv.appendChild(rtspNotifierDiv);
			hostInstance.rtspNotifier = rtspNotifierDiv;
		}
	} else {
		hostInstance.rtspNotifier = rtspNotifierDiv;
	}
	return rtspNotifierDiv;
}

function createDetailMenu(classInstance) {
	// Unified detail menu creator for both hosts and groups classes
	const itemType = classInstance.type;
	const hashID = classInstance.hashID;
	// console.log(`Creating ${itemType} detail menu for:`, item);
	const menuElement = document.createElement('div');
	menuElement.className = 'hostMenuElement';
	menuElement.id = `${itemType}MenuElement_${hashID}`;
	menuElement.setAttribute('type', itemType);
	const menuElementInner = document.createElement('div');
	menuElementInner.className = 'hostMenuElementInner';
	menuElementInner.id = `${itemType}MenuElementInner_${hashID}`;
	menuElement.appendChild(menuElementInner);
	const hamburgerLabel = document.createElement('label');
	hamburgerLabel.setAttribute('for', `open${itemType.charAt(0).toUpperCase() + itemType.slice(1)}MenuID_${hashID}`);
	hamburgerLabel.className = 'hostMenuIconToggle';
	const hamburgerMenu = document.createElement('div');
	hamburgerMenu.className = `hostMenu hostMenu_${hashID}`;
	hamburgerMenu.id = `hamburgerMenu_${hashID}`;
	const hamburgerMenuOverlay = document.createElement('div');
	hamburgerMenuOverlay.className = 'hostMenuOverlay';
	hamburgerMenuOverlay.title = "Toggling these controls will mass set every host in the group.  Caution."
	hamburgerMenu.appendChild(hamburgerMenuOverlay);
	hamburgerMenuOverlay.addEventListener('click', function(e) {
		e.preventDefault();
		e.stopPropagation();
		const checkbox = menuElement.querySelector('.openHostMenuCheckbox');
		if (checkbox && checkbox.checked) {
			closeSingleMenu(checkbox);
		}
	});
	const hamburgerCheckBox = document.createElement('input');
	hamburgerCheckBox.type = 'radio';
	hamburgerCheckBox.name = 'menuRadioCheck';
	hamburgerCheckBox.className = 'openHostMenuCheckbox openHostMenu';
	hamburgerCheckBox.id = `open${itemType.charAt(0).toUpperCase() + itemType.slice(1)}MenuID_${hashID}`;
	hamburgerCheckBox.setAttribute('data-hash', hashID);
	hamburgerLabel.innerHTML = `
		<div class="spinner diagonal part-1"></div>
		<div class="spinner horizontal"></div>
		<div class="spinner diagonal part-2"></div>
		`;
	menuElementInner.appendChild(hamburgerCheckBox);
	menuElementInner.appendChild(hamburgerLabel);
	menuElementInner.appendChild(hamburgerMenu);
	// Use the provided menu set creator function
	const menuContents = createMenuSet(classInstance);
	hamburgerMenu.appendChild(menuContents);
	hamburgerCheckBox.addEventListener('click', function (e) {
		e.stopPropagation();
		if (this.dataset.waschecked === 'true') {
			e.preventDefault();
			this.checked = false;
			this.dataset.waschecked = 'false';
			updateMenuState(this);
		} else {
			this.dataset.waschecked = 'true';
			updateMenuState(this);
			const siblings = document.querySelectorAll(`input[name="${this.name}"]`);
			siblings.forEach(sib => {
				if (sib !== this) {
					sib.checked = false;
					sib.dataset.waschecked = 'false';
					updateMenuState(sib);
				}
			});
		}
	});
	hamburgerLabel.addEventListener('click', function (e) {
		e.preventDefault();
		hamburgerCheckBox.click();
	});
	return menuElement;
}

function updateMenuState(checkbox) {
	const hash = checkbox.dataset.hash;
	// console.log(`[updateMenuState] Called for hash: ${hash}`);
	const menu = document.getElementById(`hamburgerMenu_${hash}`);
	if (!menu) return;
	const isActive = checkbox.checked;
	if (isActive) {
		menu.classList.add('active');
		menu.style.opacity = '1';
		menu.style.pointerEvents = 'auto';
	} else {
		menu.classList.remove('active');
		menu.style.opacity = '0';
		menu.style.pointerEvents = 'none';
		// console.log(`[updateMenuState] Closing menu, hiding from interaction`);
	}
}

function createTextBox(itemInstance, spanText, targetAttribute) {
	// takes the input object, the desired text for the label span and the specific attribute it is to work upon
	// for groups, it can also take a subOperation argument
	// console.info(`Generating a textbox for:`, itemInstance);
	let labelDiv = document.createElement("div");
	let labelSpan = document.createElement("span");
	labelSpan.textContent = spanText;
	labelSpan.classList.add("label");
	labelDiv.appendChild(labelSpan);
	labelDiv.classList.add('detailMenu_container');
	// Generates a text box based on input parameters
	let labelTextBox = document.createElement("input");
	// console.log("Creating textbox with span text: " + spanText + " for a: " + itemInstance.type + ", targeting attr: " + targetAttribute)
	let currentValue;
	if (itemInstance.controls?.[targetAttribute] !== undefined) {
		currentValue = itemInstance.controls?.[targetAttribute] || "not populated";
	} else if (itemInstance[targetAttribute] !== undefined) {
		currentValue = itemInstance[targetAttribute] || "not populated";
	} else {
		currentValue = "not populated";
	}
	const placeholderText = {
		label : itemInstance.controls.label,
		blueToothMAC: "ex., AA:BB:CC:DD:EE:FF",
		liveStreamURL: "ex. https://abc.com/watch?v=ID",
		liveStreamKey: "ex. your_api_key_here",
		bannerContent: "ex. DOC CAM",
	};
	labelTextBox.setAttribute("placeholder", placeholderText[targetAttribute] || "Enter value...");
	labelTextBox.setAttribute("type", "text");
	labelTextBox.setAttribute("class", "inputTextbox");
	labelTextBox.setAttribute("title", "Click and enter text to change this data, it will become set on click-off");
	labelTextBox.dataset.originalValue = currentValue;
	labelTextBox.dataset.targetAttribute = targetAttribute; // Store for reference
	labelTextBox.innerHTML = escapeHTML(itemInstance.controls?.[targetAttribute] || itemInstance[targetAttribute] || "");
	labelTextBox.addEventListener('focus', function () {
		let oldLabelValue = this.value;
		console.log('picking up text: ' + oldLabelValue);
	});
	labelTextBox.addEventListener('blur', function () {
		let oldLabelValue = this.innerHTML;
		let updatedText = escapeHTML(this.value);
		if (oldLabelValue === updatedText) {
			console.log("Values have not changed, doing nothing");
		} else {
			console.log("Submitting label update with values\nHash: " + itemInstance.hashID + "\nNew Label: " + updatedText);
			// ["hash"] ?? null; // hash ID of the element, can be null in case of new group rq
			// ["request"] ?? null; // operation we are performing on the element
			// ["data"] ?? null; // further data for suboperations and values etc.
			// ["parentHash"] ?? null; // the parent hash if needed
			// ["type\"]; //  GROUP, HOST, INPUT, GLOBALS
			if (itemInstance instanceof Group) {
				void window.root.controlRequestManager.send({
					operation: "GROUPCONTROL",
					parentHash: itemInstance.hashID,
					parentType: "group",
					controlKey: `relabel:${updatedText}`,
					controlValue: "",
					toggleOn: false
				});
			} else {
				// we could only be a host otherwise
				window.root.controlRequestManager.send({
					operation: "HOSTCONTROL",
					parentHash: itemInstance.hashID,
					parentType: "host",
					controlKey: `relabel:${updatedText}`,
					controlValue: "",
					toggleOn: false
				}).then(() => {
					// For class instances, update the controls object directly
					itemInstance.controls.labelText = updatedText;
				});
			}
		}
	});
	labelDiv.appendChild(labelTextBox);
	// Return a whole div with span text and the label text box
	return labelDiv;
}

function createFilePicker(objectData) {
	// A simple browser filepicker.
	// We need to add some type checking here to ensure only image files are able to be uploaded
	// We also need to enforce a size limit both here, and on the PHP backend.
	let fileDiv = document.createElement("div");
	let fileSpan = document.createElement("span");
	fileSpan.setAttribute("title", "Upload a file to become the image served by this group's Static Image input option.");
	fileSpan.textContent = "Select Image File";
	fileSpan.classList.add("label");
	fileDiv.appendChild(fileSpan);
	fileDiv.classList.add('detailMenu_container');
	// Create the file input
	let fileInput = document.createElement("input");
	fileInput.type = 'file';
	fileInput.accept = 'image/*';
	fileInput.onchange = async e => {
		let file = e.target.files[0];
		if (!file) return;
		if (!file.type.startsWith('image/')) {
			alert('Invalid file type. Must be an image.');
			fileInput.value = '';
			return;
		}
		const MAX_SIZE = 5 * 1024 * 1024; // 5MB
		if (file.size > MAX_SIZE) {
			alert('File size too large. Maximum size is 5MB.');
			fileInput.value = '';
			return;
		}
		// Resolution check (1920x1080 max, this is our standard resolution)
		const img = new Image();
		const url = URL.createObjectURL(file);
		img.onload = function() {
			if (img.width > 1920 || img.height > 1080) {
				alert('Resolution exceeds maximum (1920x1080).');
				fileInput.value = '';
			}
			URL.revokeObjectURL(url); // Prevent memory leaks
		};
		img.onerror = function() {
			alert('Invalid image format. Please select a valid image.');
			fileInput.value = '';
			URL.revokeObjectURL(url);
		};
		img.src = url;
		// Read file as base64
		const reader = new FileReader();
		reader.onload = function(event) {
			// Remove the data:uri prefix
			let base64Data = event.target.result;
			if (base64Data.includes('base64,')) {
				base64Data = base64Data.split('base64,')[1];
			}
			// Ensure the base64 string is padded
			base64Data += '='.repeat((4 - (base64Data.length % 4)) % 4);
			// Prepare the data to send
			const payload = {
				operation: "GROUPCONTROL",
				parentHash: objectData.hashID,
				parentType: "GROUP",
				controlKey: `staticImage`,
				controlValue: base64Data,
				toggleOn: false
			};
			// Send the request
			window.root.controlRequestManager.send(payload);
		};
		reader.readAsDataURL(file);
	};
	fileDiv.appendChild(fileInput);
	// Return a whole div with span text and the label text box
	return fileDiv;
}

function createMenuSet(item) {
	// Unified menu set creator - uses item.type to determine button population
	const menuConfig = {
		group: [
			{
				label: '🔄 REBOOT',
				title: 'Reboot all hosts in this group',
				operation: 'GROUPCONTROL',
				toggleKey: 'rebootStatus',
				value: '0'
			},
			{
				label: '⚙️ RESET',
				title: 'Reset configuration for this group',
				operation: 'GROUPCONTROL',
				toggleKey: 'resetStatus',
				value: '0'
			},
			{
				label: '👁️ REVEAL',
				title: 'Show SMPTE test card on all hosts in this group',
				operation: 'GROUPCONTROL',
				toggleKey: 'revealStatus',
				value: '0'
			},
			// Group DELETE key
			{
				label: '🗑️ DELETE',
				title: 'Delete this group, and move all hosts to the primary group',
				operation: 'deleteGroup',
				value: null,
				condition: (item) => {
					return !item.isPrimary;
				}
			}
		],
		host: [
			{
				label: '🗑️ DEPROVISION',
				title: 'Remove this host from the system',
				operation: 'HOSTCONTROL',
				toggleKey: 'deprovision',
				value: '0'
			},
			{
				label: '👁️ REVEAL',
				title: 'Show an SMPTE test card on this host',
				operation: 'HOSTCONTROL',
				toggleKey: 'revealStatus',
				value: '1'
			},
			{
				label: '⚙️ RESET',
				title: 'Reset host video compression and display tasks',
				operation: 'HOSTCONTROL',
				toggleKey: 'resetStatus',
				value: '0'
			},
			{
				label: '🔄 REBOOT',
				title: 'Reboot this decoder',
				operation: 'HOSTCONTROL',
				toggleKey: 'rebootStatus',
				value: '0'
			},
			{
				label: '',
				title: 'Switch on/off encoding functionality on this host',
				operation: 'HOSTCONTROL',
				toggleKey: 'promote',
				value: item.controls.promote ?? 0
			},
			{
				// Note that this is NOT the UI Notifier, this is the UI button in the detailMenuSet
				label: '',
				title: 'Switch on/off the web interface for this host',
				operation: 'HOSTCONTROL',
				toggleKey: 'UIEnable',
				value: item.controls.UIEnable ?? 0
			}
		],
		svr: [
			{
				label: '⚙️ RESET',
				title: 'Reset host video compression and display tasks to defaults',
				operation: 'HOSTCONTROL',
				toggleKey: 'resetStatus',
				value: '0'
			},
			{
				label: '🔄 REBOOT',
				title: 'Reboot the server',
				operation: 'HOSTCONTROL',
				toggleKey: 'rebootStatus',
				value: '0'
			},
			{
				// Note that this is NOT the UI Notifier, this is the UI button in the detailMenuSet
				label: '',
				title: 'Switch on/off the web interface for this host',
				operation: 'HOSTCONTROL',
				toggleKey: 'UIEnable',
				value: item.controls.UIEnable ?? 0
			}
		],
		net: [
			// net devices can be very varied so just about all we can do with them is reboot or remove them
			// this could (eventually) be either REST calls for supported devs, or we could power cycle the switchport?
			{
				label: '🔄 REBOOT',
				title: 'Attempt to reboot this device',
				operation: 'HOSTCONTROL',
				toggleKey: 'rebootStatus',
				value: '0'
			},
			{
				label: '🗑️ DEPROVISION',
				title: 'Remove this host from the system',
				operation: 'HOSTCONTROL',
				toggleKey: 'deprovision',
				value: '0'
			}
		],
	};
	let buttonList;
	if (item.hostType === "svr") {
		console.info("Item host type is a server, generating limited menu set options.");
		// We don't want deprovision and switch buttons for the server, they aren't valid for this host type.
		buttonList = menuConfig[item.hostType] || [];
	} else if (item.hostType === "net") {
		console.info("Item host type is a net device, generating limited menu set options.");
		buttonList = menuConfig[item.hostType] || [];
	} else {
		console.info("Item host type is a standard host, generating full host options.");
		buttonList = menuConfig[item.type] || [];
	}
	const menuSet = document.createElement('div');
	menuSet.id = `hamburgerMenuContents_${item.hashID}`;
	menuSet.classList.add('hamburger-menu');
	menuSet.title = "Advanced controls for object";
	const elementDiv = document.createElement('div');
	let groupHash;
	for (const buttonDef of buttonList) {
		// Handle both old string format and new object format for backward compatibility
		elementDiv.classList.add('detailMenu_container');
		const label = typeof buttonDef === 'string' ? buttonDef : buttonDef.label;
		const title = typeof buttonDef === 'string' ? label : buttonDef.title;
		const toggleKey = typeof buttonDef === 'string' ? label : buttonDef.toggleKey;
		const buttonOperation = typeof buttonDef === 'string' ? label : buttonDef.operation;
		const condition = typeof buttonDef === 'object' ? buttonDef.condition : null;
		if (item.type === "group") {
			groupHash = item.hashID;
		} else if (item.type === "host") {
			groupHash = item.controls.GROUP;
		}
		const value = typeof buttonDef === 'object' ? buttonDef.value : '1';
		// Skip button if condition is not met
		if (condition && !condition(item)) {
			// console.log(`Skipping ${label} - condition not met for`, item);
			continue;
		}
		const button = createUnifiedButton({
			parentItem: item,
			parentHash: item.hashID,
			groupHash: groupHash,
			control: toggleKey,
			title: title, // the button's hover tooltip
			dataLabel: label, // the button's initial text on the UI
			operation: buttonOperation, // the kind of operation we are performing
			value: value, // the value we parse (in this case an on/of toggle)
			buttonCategory: "HOST", // This is the initial type switch for PHP to process.
			toggleOn: true,
		});
		elementDiv.appendChild(button);
	}
	// ScreenCast toggle element for hosts
	// appears only if we are an encoder AND screencastCapable is 1
	if ((item.controls.type === "ENC" || item.controls.type === "svr")) {
		console.log("Host is screencast capable, generating additional control..")
		if ((item.controls.screencastCapable === "1")) {
			const screenCastButton = createUnifiedButton({
				parentItem: item,
				parentHash: item.hashID,
				groupHash: groupHash,
				control: "enableScreenCast",
				title: "Start/Stop screen casting",
				dataLabel: "	ScreenCast Off",
				operation: "HOSTCONTROL",
				value: "0",
			});
			elementDiv.appendChild(screenCastButton);
		}
	}
	menuSet.appendChild(elementDiv);
	// Additional Group controls (textboxes, file pickers, dropdowns
	if (item.type === "group") {
		menuSet.appendChild(createTextBox(item, "Encoder Timeout", "encoderTimeoutSeconds", "changeEncoderTimeout"));
		menuSet.appendChild(createTextBox(item, "📶 BlueTooth MAC", "blueToothMAC", "changeBTMac"));
		menuSet.appendChild(createTextBox(item, "📺 Livestream URL",  "liveStreamURL", "changeLiveStreamSettings"));
		menuSet.appendChild(createTextBox(item, "📺 Livestream Key",  "liveStreamKey", "changeLiveStreamSettings"));
		menuSet.appendChild(createTextBox(item, "📝 Banner Text", "bannerContent", "changeBannerContent"));
		menuSet.appendChild(createFilePicker(item));
		const codecDropdown = createCodecDropdown(item);
		menuSet.appendChild(document.createTextNode("Codec"));
		menuSet.appendChild(codecDropdown);
		refreshCodecDropdown(codecDropdown, item);
	}
	return menuSet;
}

function addEmitterListener(element, parentItem, controlKeyOverride) {
	if (!parentItem?.emitter) return;
	const controlKey = controlKeyOverride || element.dataset.control || element.dataset.type || element.id;
	// Helper to update blank button text based on blankStatus
	const updateBlankButton = (btnElement, value) => {
		const isBlank = value === "1" || value === true || value === "true";
		const textSpan = btnElement.querySelector('.btn__label > span');
		const labelSpan = btnElement.querySelector('.btn__label');
		if (textSpan && labelSpan) {
			const newText = isBlank
				? btnElement.dataset.toggleTextOn || "⬜ UN-BLANK"
				: btnElement.dataset.toggleTextOff || "⬛ BLANK";
			textSpan.textContent = newText;
			labelSpan.setAttribute('data-label', newText);
			labelSpan.dataset.label = newText;
			btnElement.dataset.value = value;
			btnElement.classList.add('updating');
			requestAnimationFrame(() => {
				btnElement.classList.remove('updating');
			});
		}
	};
	// Helper to update toggle button text (promote, UIEnable, etc.)
	const updateToggleButton = (btnElement, value) => {
		const isOn = value === "1" || value === true;
		const textSpan = btnElement.querySelector('.btn__label > span');
		const labelSpan = btnElement.querySelector('.btn__label');
		if (textSpan && labelSpan) {
			const newText = isOn
				? btnElement.dataset.toggleTextOn || btnElement.dataset.label
				: btnElement.dataset.toggleTextOff || btnElement.dataset.label;
			textSpan.textContent = newText;
			labelSpan.setAttribute('data-label', newText);
			labelSpan.dataset.label = newText;
			btnElement.dataset.value = value;
			btnElement.classList.add('updating');
			requestAnimationFrame(() => {
				btnElement.classList.remove('updating');
			});
		}
	};
	// Helper to update health indicator by replacing the DOM element
	const updateHealthIndicator = (hostInstance) => {
		const parentElement = hostInstance.element;
		if (parentElement) {
			const hostButtonsDiv = parentElement.querySelector('.host-buttons');
			if (hostButtonsDiv) {
				const existingHealthBox = hostButtonsDiv.querySelector(`#health-${hostInstance.hashID}`);
				if (existingHealthBox) {
					const newHealthBox = createHealthIndicator(hostInstance);
					hostButtonsDiv.replaceChild(newHealthBox, existingHealthBox);
				}
			}
		}
	};
	// Helper to update UI notifier element visibility
	const updateUINotifier = (hostInstance, value) => {
		const uiNotifier = hostInstance.uiNotifier;
		if (uiNotifier) {
			const valueStr = String(value);
			const isEnabled = valueStr === "1" || value === true;
			if (isEnabled) {
				createUINotifier(hostInstance);
			} else {
				uiNotifier.remove();
			}
		}
	};
	// Store the subscription callback reference so we can unsubscribe later
	const subscriptionCallback = (data) => {
		const { controlName, newValue, oldValue } = data;
		const matchesControl = controlName === controlKey ||
			controlName === element.dataset.control ||
			(element.dataset.control && controlName === element.dataset.control);
		if (!matchesControl) return;
		switch (element.tagName) {
			case 'A':
				if (controlName === 'blankStatus') updateBlankButton(element, newValue);
				else if (['promote', 'UIEnable'].includes(controlName)) updateToggleButton(element, newValue);
				break;
			case 'DIV':
				if (controlName === 'healthStatus' && element.id?.startsWith('health-')) {
					updateHealthIndicator(parentItem);
				} else if (controlName === 'UIEnable' && (element.id === 'ui-notifier' || element.dataset.control === 'UIEnable')) {
					updateUINotifier(parentItem, newValue);
					const textSpan = element.querySelector('.btn__label > span');
					const labelSpan = element.querySelector('.btn__label');
					if (textSpan && labelSpan) {
						const isON = newValue === "1" || newValue === true;
						const newText = isON ? element.dataset.toggleTextOn : element.dataset.toggleTextOff;
						textSpan.textContent = newText;
						labelSpan.setAttribute('data-label', newText);
					}
				}
				break;
			case 'INPUT':
				if (element.type === 'checkbox' && (controlName === element.dataset.control || controlName === element.name)) {
					element.checked = newValue === "1" || newValue === true || newValue === "true";
				} else if (element.type === 'text' || element.type === 'email') {
					element.value = newValue || '';
				}
				break;
			case 'SELECT':
				if (element.id.includes(controlName) || element.dataset.control === controlName) {
					element.value = newValue || '';
					element.dispatchEvent(new Event('change'));
				}
				break;
			default:
				if (element.dataset.control === controlName) {
					element.dataset.value = newValue;
				}
				break;
		}
		element.dispatchEvent(new CustomEvent('emitterUpdate', {
			detail: { controlName, newValue, oldValue }
		}));
	};
	parentItem.emitter.on('controlUpdate', subscriptionCallback);
	// Attach cleanup method to the element for later removal
	element._cleanupEmitter = () => {
		parentItem.emitter.off('controlUpdate', subscriptionCallback);
		delete element._cleanupEmitter;
	};
	return `${parentItem.hashID}-${controlKey}`;
}

function createUnifiedButton(options) {
	// Unified function to create different types of buttons
	// Provided with the following options data:
	// parentItem: item,
	// parentHash: item.hashID,
	// groupHash: the group's hash ID
	// control: the target control (if any)
	// title: title, // the button's hover tooltip
	// dataLabel: label, // the button's text on the UI
	// operation: "HOSTCONTROL", // the kind of operation we are performing
	// value: value, // the value we parse (in this case an on/of toggle)
	// buttonCategory: "HOST" // This is the initial type switch for PHP to process.
	// console.log ("Generating button with values:", options);
	const button = document.createElement('a');
	const buttonDataSetProperties = {
		parentItem: options.parentItem || "ERROR",
		parentHash: options.parentHash || "ERROR",
		groupHash: options.groupHash || null,
		control: options.control || null,
		title: options.title || "ERROR",
		label: options.dataLabel || "",
		operation: options.operation || "",
		value: options.value || "0",
		type: options.buttonCategory || "",
		toggleOn: options.toggleOn || false
	};
	for (const [key, keyValue] of Object.entries(buttonDataSetProperties)) {
		button.dataset[key] = keyValue === undefined || keyValue === null ? '' : String(keyValue);
	}
	const innerSpan = document.createElement('span');
	const labelSpan = document.createElement('span');
	const backgroundSpan = document.createElement('span');
	const textSpan = document.createElement('span');
	const backgroundOuter = document.createElement('span');
	if (button.dataset.type === "INPUT") {
		const groupInstance = window.root.groups.get(options.groupHash);
		if (!groupInstance) {
			console.error('Must have a parent group, but group hash ID: ' + button.dataset.groupHash + ' not found!');
			return;
		}
		labelSpan.dataset.hover = '▶';
		labelSpan.dataset.activated = '✔';
		button.addEventListener('click', function () {
			groupInstance.setActiveInput(button.dataset.parentHash);
		});
	} else {
		// We are not an input button
		// These are statements for buttons whose label should reflect their value 0/1
		if (button.dataset.control === "blankStatus") {
			button.dataset.toggleTextOn = "⬜ UN-BLANK";
			button.dataset.toggleTextOff = "⬛ BLANK";
		} else if (button.dataset.control === "promote") {
			button.dataset.toggleTextOn = "	ENC ON";
			button.dataset.toggleTextOff = "	ENC OFF";
		} else if (button.dataset.control === "UIEnable") {
			button.dataset.toggleTextOn = "	UI ON";
			button.dataset.toggleTextOff = "	UI OFF";
		} else {
			// These buttons don't need to display their status, as they set flags which are rapidly reset.
			button.dataset.toggleTextOff = button.dataset.label;
			button.dataset.toggleTextOn = button.dataset.label;
		}
		let currentValue = button.dataset.value || null;
		let newValue = null;
		button.dataset.label = (
			currentValue === "0" ||
			currentValue === "false" ||
			currentValue === false ||
			currentValue === null
		)
			? button.dataset.toggleTextOff
			: button.dataset.toggleTextOn;
		// Event listener
		button.addEventListener('click', function () {
			console.info("Clicked button:", button.dataset.label);
			// Only toggle if this is a toggle-type button
			const isToggleType =
				button.dataset.toggleOn === "true" ||
				button.dataset.toggleOn === true ||
				options.toggleOn === true;
			if (isToggleType) {
				newValue = button.dataset.value === "1" ? "0" : "1";
				console.log(`Sending ${button.dataset.control}: ${currentValue} → ${newValue}`);
			}
			// Update the button's label
			window.root.controlRequestManager.send({
				operation: button.dataset.operation,
				parentHash: button.dataset.parentHash || null,
				parentType: button.dataset.parentType,
				controlKey: button.dataset.control || "null-control",
				controlValue: newValue,
				toggleOn: isToggleType
			}).then(() => {
				// console.log(`Toggle request sent for ${button.dataset.control}:`);
				button.dataset.value = newValue;
				let newText = (button.dataset.value === "0")
					? button.dataset.toggleTextOff
					: button.dataset.toggleTextOn;
				if (textSpan && labelSpan) {
					textSpan.textContent = newText;
					labelSpan.dataset.label = newText;
					// console.log("Updating button span content to:", newText);
					labelSpan.setAttribute('data-label', newText);
					void button.offsetHeight;
					button.classList.add('updating');
					requestAnimationFrame(() => {
						button.classList.remove('updating');
					});
				}
			}).catch(error => {
				console.error(`Toggle failed for ${button.dataset.control}:`, error);
			});
		});
	}
	if (!textSpan.textContent) {
		textSpan.textContent = button.dataset.label;
	}
	button.dataset.parentType = options.parentItem?.category || options.parentItem?.dataset?.type || options.buttonCategory || "UNKNOWN";
	button.className = 'btn';
	// Create button structure
	innerSpan.className = 'btn__inner';
	labelSpan.className = 'btn__label';
	labelSpan.title = button.dataset.label;
	labelSpan.dataset.label = button.dataset.label;
	backgroundSpan.className = 'btn__label__background';
	labelSpan.appendChild(textSpan);
	innerSpan.appendChild(labelSpan);
	labelSpan.dataset.hover = '▶';
	backgroundOuter.className = 'btn__background';
	button.appendChild(innerSpan);
	button.appendChild(backgroundOuter);

	// Pre-measure and lock width for toggle buttons
	if (button.dataset.control === "blankStatus" ||
		button.dataset.control === "promote" ||
		button.dataset.control === "reveal") {
		requestAnimationFrame(() => {
			const originalText = textSpan.textContent;
			const originalWidth = labelSpan.offsetWidth;
			// Determine alternative text based on operation
			let altTextState = '';
			switch (button.dataset.control) {
				case "blankStatus":
					altTextState = button.dataset.value === "1" ? '⬛ BLANK' : '⬜ UN-BLANK';
					break;
				case "promote":
					altTextState = button.dataset.value === "0" ? ' ENC ON' : ' ENC OFF';
					break;
				case "reveal":
					altTextState = button.dataset.value === "0" ? '️ REVEAL' : '️ STOP REVEAL';
					break;
			}
			if (altTextState) {
				// Temporarily set to alternate text to measure
				textSpan.textContent = altTextState;
				labelSpan.dataset.label = altTextState;
				// Force layout recalc
				const altWidth = labelSpan.offsetWidth;
				// Set to the larger of the two widths
				const maxWidth = Math.max(originalWidth, altWidth);
				labelSpan.style.minWidth = maxWidth + 'px';
				// Restore original text
				textSpan.textContent = originalText;
				labelSpan.dataset.label = originalText;
			}
		});
	}
	addEmitterListener(button, options.parentItem);
	return button;
}


//
//
// Input Specific code
//
//

function createInputElement(inputInstance) {
	// console.debug("Generating input element:", inputInstance);
	let divEntry = document.createElement("Div");
	divEntry.classList.add('input_divider_device');
	inputInstance.category = "INPUT";
	divEntry.setAttribute("data-input-hash", inputInstance.hashID);
	// This is an expected array for the createUnifiedButton function
	const parentHost = window.root.hosts.get(inputInstance.hostHash);
	if (!parentHost) {
		console.error(`FATAL: No host found for input ${inputInstance.hashID} (hostHash: ${inputInstance.hostHash})`);
		console.error("Available hosts:", Array.from(window.root.hosts.keys()));
		return divEntry;
	}
	// console.info("Parent Host Instance: ", parentHost);
	const parentGroup = window.root.groups.get(parentHost.controls.GROUP);
	if (!parentGroup) {
		console.error(`FATAL: No group found for input ${inputInstance.hashID}`);
		console.error(`  Parent host hash: ${inputInstance.hostHash}`);
		console.error(`  Parent host GROUP control: ${parentHost.controls.GROUP}`);
		console.error(`  Available groups:`, Array.from(window.root.groups.keys()));
		return divEntry;
	}
	// Only create parentObject after confirming parentGroup exists
	const parentObject = {
		hashID: inputInstance.hashID,
		type: inputInstance.type,
		group: parentGroup.hashID
	};
	// console.log("Generating an input with label: " + inputInstance.labelText + " hash: " + inputInstance.hashID);
	const activateButton = createUnifiedButton({
		parentItem: parentObject,
		parentHash: inputInstance.hashID,
		groupHash: parentHost.controls.GROUP,
		title: "Activate This Input",
		dataLabel: inputInstance.labelText,
		operation: "activate_input",
		value: inputInstance.hashID,
		buttonCategory: "INPUT",
	});
	if (window.root.globals.lowInformationMode === false) {
		// Create an input rename button
		const renameButton = createUnifiedButton({
			parentItem: parentObject,
			parentHash: inputInstance.parentHash,
			groupHash: parentHost.controls.GROUP,
			title: "Rename This Input",
			dataLabel: "RENAME",
			operation: "relabel",
			value: "relabel",
			buttonCategory: "relabel"
		});
		divEntry.appendChild(renameButton);
	}
	// Container for device-specific inline controls
	const deviceControlsDiv = document.createElement("div");
	deviceControlsDiv.classList.add('device_controls_inline');

	// NDI
	// 	NDI logo or close equivalent
	// 	directMode toggle switch, sets backend directmode 0 or 1
	// RTSP
	// 	RTSP logo or close equivalent
	// 	directMode toggle switch, sets backend directmode 0 or 1
	if (inputInstance.subType === "NDI" || inputInstance.subType === "RTSP") {
		const directToggle = createToggleBox(parentHost, "directMode", "DIRECT MODE");
		directToggle.title = "Toggles direct mode on/off.  If off, this net device will run via the UltraGrid Encoder.";
		// TODO workshop this to make it look more recognizable
		deviceControlsDiv.appendChild(document.createTextNode(` ${inputInstance.subType} `));
		deviceControlsDiv.appendChild(directToggle);
	}
	// TODO Chrome or MiraCast or apple play devices.
	// 	appropriate logo/notifier.
	// 	Enable/Disable toggle + an authentication box that pops up with connecting dev's hostname via SSE
	// 	to be implemented in backend, but want the control code in place.
	if (inputInstance.subType === "chrome" || inputInstance.subType === "miracast" || inputInstance.subType === "appleplay") {
		// Casting toggle
		const castingToggle = createToggleBox(parentObject, "casting", "CAST " + inputInstance.subType.toUpperCase());
		deviceControlsDiv.appendChild(castingToggle);
		// Authentication clicker for device pairing
		// TODO - needs plumbing into an SSE handler to update the label w/ device HostName once it attempts connection.
		// only once authorized will the streaming be allowed to commence.
		// hostHash/controls/castingToggle -- 0/1
		// hostHash/controls/castingHostRequest -- hostname
		// hostHash/controls/castingAuthorized -- hostname
		// last two keys must match for backend to switch and start encoding casting.
		const authButton = createUnifiedButton({
			parentItem: parentObject,
			parentHash: inputInstance.hashID,
			groupHash: parentHost.controls.GROUP,
			control: "authenticate",
			title: "Pair new device for " + inputInstance.subType + " casting",
			dataLabel: "AUTH DEVICE",
			operation: "INPUTCONTROL",
			value: "pair",
			buttonCategory: "INPUT",
			toggleOn: false
		});
		divEntry.appendChild(authButton);
		// Add placeholder for device hostname display (to be populated via SSE)
		const deviceNameDiv = document.createElement("div");
		deviceNameDiv.className = 'device-name-display';
		deviceNameDiv.id = 'device-name-' + inputInstance.hashID;
		deviceNameDiv.textContent = 'No device connected';
		deviceNameDiv.title = 'Connected device hostname will appear here';
		divEntry.appendChild(deviceNameDiv);
	}
	// USB
	// 	no special controls
	// PCI
	// 	no special controls
	// MIPI
	// 	no special controls
	// Other?
	// 	?????
	divEntry.appendChild(activateButton);
	if (deviceControlsDiv.children.length > 0) {
		divEntry.appendChild(deviceControlsDiv);
	}
	return divEntry;
}

async function createGroupElement(groupItem) {
	// This creates an element for each group that exists in etcd
	const hostControlDiv = document.getElementById('HostControlDiv');
	if (!(groupItem instanceof Group)) {
		groupItem = new Group(groupItem);
	}
	// Check if the DOM element already exists to prevent duplicates on page refresh
	const existingElement = document.querySelector(`[data-hash="${groupItem.hashID}"][data-type="group"]`);
	if (existingElement) {
		// Update the existing element's swatch color and ensure the groupItem.element reference is set
		existingElement.style.backgroundColor = groupItem.controls.swatchValue || "#0f2b39";
		groupItem.element = existingElement;
		return existingElement;
	}
	let divEntry = document.createElement("div");
	groupItem.category = "GROUP";
	divEntry.classList.add('groups_divider_inner');
	divEntry.setAttribute("title", `Group ${groupItem.controls.label}`);
	divEntry.setAttribute("data-type", "group");
	divEntry.setAttribute("draggable", "true");
	divEntry.setAttribute("data-hash", groupItem.hashID);
	hostControlDiv.appendChild(divEntry);
	// Add drag events
	divEntry.addEventListener("dragstart", window.root.dragDropManager.handleDragStart.bind(window.root.dragDropManager));
	divEntry.addEventListener("dragend", window.root.dragDropManager.handleDragEnd.bind(window.root.dragDropManager));
	divEntry.addEventListener('dragover', window.root.dragDropManager.handleDragOver.bind(window.root.dragDropManager));
	divEntry.addEventListener('drop', window.root.dragDropManager.handleDrop.bind(window.root.dragDropManager));
    // add a silly animation pulse
    divEntry.classList.add('group-created-animation');
    // Remove the animation class after the animation completes
    setTimeout(() => {
        divEntry.classList.remove('group-created-animation');
    }, 500);
	// Generates a header div, and two subdivs for proper position of control elements
	let groupHeaderDiv = document.createElement("div");
	groupHeaderDiv.className = 'group_header_div';
	let groupHeaderControlsDiv = document.createElement("div");
	groupHeaderControlsDiv.className = 'group_control_div';
	let groupHeaderTogglesDiv = document.createElement("div");
	groupHeaderTogglesDiv.className = 'toggle_control_div';
	// Add the blank button
	let groupBlankDiv = document.createElement("div");
	groupBlankDiv.classList.add('group_control_row_div');
	groupBlankDiv.setAttribute('title', "En-masse display blank control for every host in this group");
	groupBlankDiv.textContent = "GROUP VIDEO OUT:";
	groupBlankDiv.appendChild(createUnifiedButton({
		// parentItem: item,
		// parentHash: item.hashID,
		// groupHash: the group's hash ID
		// control: the target control (if any)
		// title: title, // the button's hover tooltip
		// dataLabel: label, // the button's text on the UI
		// operation: "HOSTCONTROL", // the kind of operation we are performing
		// value: value, // the value we parse (in this case an on/of toggle)
		// buttonCategory: "HOST" // This is the initial type switch for PHP to process.
		parentItem: groupItem,
		parentHash: groupItem.hashID,
		groupHash: groupItem.hashID,
		control: "blankStatus",
		title: "Toggle display output on every host in this group (ignores encoders, server - these must be set manually)",
		dataLabel: "⬛ BLANK",
		operation: "GROUPCONTROL",
		value: groupItem.controls.blankStatus,
		buttonCategory: "GROUP",
		toggleOn: true,
	}));
// Add the static buttons.
// These options instruct any UltraGrid display device to switch to a locally generated display input
	let groupStaticsDiv = document.createElement("div");
	groupStaticsDiv.classList.add('static_buttons_container');
	if (groupItem.controls.chainedToGroup) {
		groupStaticsDiv.classList.add('hidden');
	}
	let staticsSpan = document.createElement("span");
	staticsSpan.textContent = "COMMON SOURCES";
	staticsSpan.title = "Common sources are run locally on each display device, in order to save network bandwidth.";
	staticsSpan.classList.add("label");
	groupStaticsDiv.appendChild(staticsSpan);
// Black Screen button
	groupStaticsDiv.appendChild(createUnifiedButton({
		parentItem: groupItem,
		parentHash: "0",
		groupHash: groupItem.hashID,
		control: null,
		title: "Activate This Input",
		dataLabel: "BLACK SCRN",
		operation: "activate_input",
		value: "0",
		buttonCategory: "INPUT",
		toggleOn: false
	}));
// Static Image button
	groupStaticsDiv.appendChild(createUnifiedButton({
		parentItem: groupItem,
		parentHash: "1",
		groupHash: groupItem.hashID,
		control: null,
		title: "Activate This Input",
		dataLabel: "STATIC IMAGE",
		operation: "activate_input",
		value: "1",
		buttonCategory: "INPUT",
		toggleOn: false
	}));
// Test Card button
	groupStaticsDiv.appendChild(createUnifiedButton({
		parentItem: groupItem,
		parentHash: "2",
		groupHash: groupItem.hashID,
		control: null,
		title: "Activate This Input",
		dataLabel: "Test Card",
		operation: "activate_input",
		value: "2",
		buttonCategory: "INPUT",
		toggleOn: false
	}));
	// Creates a dropdown element for active inputs within the group
	let sourceTextDiv = document.createElement('div');
	let sourceSpan = document.createElement("span");
	sourceSpan.textContent = "SOURCES: ";
	sourceSpan.classList.add("label");
	sourceTextDiv.classList.add('group_control_row_div');
	sourceTextDiv.appendChild(sourceSpan);
	let select = await (createSourceDropdown(groupItem));
	sourceTextDiv.appendChild(select);
	groupItem.sourceDropdownElement = select;
	// If low-information mode is off, we also add toggle boxes and the advanced controls menu.
	// Label fields will also be modifiable text boxes
	if (window.root.globals.lowInformationMode === false) {
		console.log("Low information mode disabled, generating full UI");
		// Generates an element containing the GROUP: <relabel> element
		let groupLabelDiv = document.createElement("div");
		groupLabelDiv.appendChild(createTextBox(groupItem, "GROUP:","label"));
		groupLabelDiv.classList.add('group_control_row_div');
		groupLabelDiv.setAttribute('title', "The group's label designation (user-modifiable)");
		groupHeaderControlsDiv.appendChild(groupLabelDiv);
		// Generates the toggle boxes element
		let toggleBoxesDiv = document.createElement("div");
		groupHeaderTogglesDiv.classList.add("system_divider_inner");
		toggleBoxesDiv.setAttribute('title', "Group toggles and detail controls");
		const toggles = {
			persistInput: 'Persist Inputs',
			bannerStatus: 'Enable Banner',
			livestreamStatus: 'Enable Livestream',
			audioStatus: 'Enable Bluetooth'
		};
		const groupDetailMenuContainer = document.createElement("div");
		const header = document.createTextNode("Advanced Group Controls");
		const groupDetailMenu = createDetailMenu(groupItem);
		groupDetailMenuContainer.appendChild(header);
		groupDetailMenuContainer.appendChild(groupDetailMenu);
		groupHeaderTogglesDiv.appendChild(groupDetailMenuContainer);
		for (const [toggleKey, toggleLabel] of Object.entries(toggles)) {
			toggleBoxesDiv.appendChild(createToggleBox(groupItem, toggleKey, toggleLabel));
		}
		toggleBoxesDiv.appendChild(createColorSwatch(groupItem, divEntry));
		groupHeaderTogglesDiv.appendChild(toggleBoxesDiv);
		groupHeaderDiv.appendChild(groupHeaderTogglesDiv);
	} else {
		// Simple mode
		// Generates a simple header with the group name
		let groupLabelDiv = document.createElement("div");
		groupLabelDiv.appendChild(document.createTextNode(` GROUP: ${groupItem.controls.label}`));
		groupLabelDiv.classList.add('group_control_row_div');
		groupLabelDiv.setAttribute('title', "The group's label designation (user-modifiable in advanced mode)");
		groupLabelDiv.classList.add("buttons_container");
		groupHeaderControlsDiv.appendChild(groupLabelDiv);
	}
	divEntry.style.backgroundColor = groupItem.controls.swatchValue;
	// Add all of these to the generated groups element
	groupHeaderControlsDiv.appendChild(sourceTextDiv);
	groupHeaderControlsDiv.appendChild(groupBlankDiv);
	groupHeaderDiv.appendChild(groupHeaderControlsDiv);
	groupHeaderDiv.appendChild(groupStaticsDiv);
	divEntry.appendChild(groupHeaderDiv);
	// Ensure a drop listener exists for the element
	divEntry.addEventListener('drop', window.root.dragDropManager.handleDrop);
	divEntry.addEventListener('dragover', window.root.dragDropManager.handleDragOver);
	groupItem.element = divEntry;
}


//
//
// Initial page load function, initialization and SSE functions
//
//

async function handlePageLoad() {
	// Create the root object if it doesn't exist
	if (!window.root) {
		window.root = {
			codecs: {},
			// Initialize other properties as needed
			globals: {
				lowInformationMode: false
			}
		};
	}
    // This tracks groups with active inputs centrally, for quick lookups
	window.root.activeGroupInputsEmitter = new EventEmitter();
	window.root.groups = new Map();
	window.root.hosts = new Map();
	window.root.inputs = new Map();
	window.root.controlRequestManager = new ControlRequestManager();
	window.root.dragDropManager = new DragDropManager();
	// Add click-outside-to-close handler for hamburger menus
	document.addEventListener("click", function (e) {
		const isMenuElement = e.target.closest(".hostMenuElement");
		const isMenuCheckbox = e.target.classList.contains("openHostMenuCheckbox");
		const isMenuLabel = e.target.closest(".hostMenuIconToggle");
		if (isMenuElement || isMenuCheckbox || isMenuLabel) {
			return;
		}
		closeMenu();
	});
	console.log("Starting fetch calls...");
	// Call fetchData to process object instances
	await fetchData();
	await setupUIAfterAjax();
	Promise.resolve().then(() => {
		window.sseManager = new SSEManager(REALTIME_CONFIG.SSE_URL);
		window.sseManager.connect();
	});
}

function closeMenu(checkbox) {
	if (!checkbox) {
		// No specific checkbox provided — close all open menu elements
		const checkboxes = document.querySelectorAll('.openHostMenuCheckbox');
		checkboxes.forEach(function (cb) {
			closeSingleMenu(cb);
		});
		return;
	}
	closeSingleMenu(checkbox);
}

function closeSingleMenu(checkbox) {
	checkbox.checked = false;
	checkbox.dataset.waschecked = 'false';
	updateMenuState(checkbox);
}

function handleGroupEvents(event) {
	// Handles SSE events targeting group elements
	// Split our key into parts so we may access them as arraydata
	// console.log("Group event: ", event);
	const parts = event.key.split('/');
	if (parts[0] !== "GROUPS") {
		// This shouldn't have gone to this handler
		return;
	}
	const hashID = parts[1];
	// console.log("Handling a Groups event for Group hash: " + hashID);
	// Find Group with specific data-hash and data-type attributes
	// console.debug("Group class Instance: ", groupItem);
	let groupItem = window.root.groups.get(hashID);
	if (parts[3] === "newGroup" && event.value === "1") {
		// If the group already exists in the registry, don't create a new one
		if (groupItem) {
			console.log(`Group ${hashID} already exists, ignoring newGroup event.`);
			return;
		}
		const newGroup = new Group({
			hashID: hashID,
			// controls
			controls: {
				audioStatus: 0,
				blankStatus: 0,
				bannerStatus: 0,
				bannerContent: "DEFAULT",
				chainedToGroup: null,
				label: "New Group",
				livestreamStatus: 0,
				livestreamURL: null,
				livestreamKey: null,
				persistInput: 0,
				rebootStatus: 0,
				resetStatus: 0,
				revealStatus: 0,
				sourceHash: "1",
				activeCodec: "",
				isPrimary: false,
				swatchValue: "#0f2b39"
			}
		});
		window.root.groups.set(hashID, newGroup);

		createGroupElement(newGroup).then(() => {
			// Consume the newGroup flag on the backend
			void window.root.controlRequestManager.send({
				operation: "GROUPCONTROL",
				parentHash: hashID,
				parentType: "group",
				controlKey: "groupCreated",
				controlValue: 0,
				toggleOn: false
			});
			// Notify ALL dropdowns to rebuild since a new group
			if (window.root?.activeGroupInputsEmitter) {
				window.root.activeGroupInputsEmitter.emit('*');
			}
			// Also trigger source dropdown refresh event for immediate UI update
			document.dispatchEvent(new CustomEvent('sourceDropdownRefresh', {detail: newGroup}));
			newGroup.updateActiveState();
		});
	} else if (event.eventType === "DELETE") {
		console.warn("Removing group element from DOM and dataset!");
		if (groupItem) {
			groupItem.unregisterGroup(hashID);
		}
		const groupElement = document.querySelector(`[data-hash="${hashID}"][data-type="group"]`);
		if (groupElement) {
			groupElement.remove();
		}
		// Double-check: clear from window.root.groups if still present
		window.root.groups.delete(hashID);
	} else {
		try {
            // Handle control update
			let controlName = null;
            if (parts.length > 3) {
                controlName = parts[3];
            }
			if (
				controlName === "staticImage" ||
				controlName === "previousVideoSourceKey" ||
				controlName === "currentVideoSourceKey"
			) {
				return; // we don't need to update these values from the backend
			}
			// Always update controls, even if the key doesn't exist yet
			if (groupItem && groupItem.controls) {
				groupItem.controls[controlName] = event.value;
				console.log("Updated group control", controlName, "to:", event.value);
				if (controlName === "sourceHash") {
					// console.log("Calling input activation update for input hash ID: " + event.value + " in group hash ID: " + hashID);
					groupItem.sourceHash = event.value;
					groupItem.updateActiveState();
					// What defines chainedGroup and chainedHash?
					// each group has a key which can be undefined/null: group.controls.chainedToGroup
					window.root.groups.forEach(group => {
						if (group.controls.chainedToGroup === groupItem.hashID) {
							console.log(`This group is the source target of a chained group! Broadcasting source change to the chained group: ${group.hashID}`);
							// Send changeGroupSource to the chained group
							void window.root.controlRequestManager.send({
								operation: "GROUPCONTROL",
								parentHash: group.hashID,
								parentType: "group",
								controlKey: "changeGroupSource",
								controlValue: event.value,
								toggleOn: false
							});
						}
					});
				}
				if (controlName === "label") {
					// Trigger a source dropdown refresh for all groups
					if (window.root?.activeGroupInputsEmitter) {
						window.root.activeGroupInputsEmitter.emit('*');
					}
				}
				if (controlName === "chainedToGroup") {
					// force a source dropdown refresh
					// get the chained group's sourceHash and update our own sourceHash to match
					const targetGroup = window.root.groups.get(event.value);
					if (targetGroup) {
						// ADDED - define chainedHash here
						let chainedHash = targetGroup.controls.sourceHash;
						void window.root.controlRequestManager.send({
							operation: "GROUPCONTROL",
							parentHash: chainedHash,
							parentType: "group",
							controlKey: "changeGroupSource",
							controlValue: targetGroup.controls.sourceHash,
							toggleOn: false
						});
					}
					// Rebuild input button cache since chainable inputs changed
					groupItem.inputButtonMap.clear();
					document.dispatchEvent(new CustomEvent('sourceDropdownRefresh', {detail: groupItem}));
				}
				if (controlName === "swatchValue") {
					// Update group element background color
					if (groupItem.element) {
						groupItem.element.style.backgroundColor = event.value;
					}
					// Update color swatch and picker
					const picker = document.getElementById(`swatch-group-${hashID}`);
					if (picker) {
						picker.value = event.value;
						const swatch = picker.parentNode;
						if (swatch && swatch.classList.contains('color-swatch')) {
							swatch.style.backgroundColor = event.value;
						}
					}
				}
				if (window.root && window.root.activeGroupInputsEmitter) {
					window.root.activeGroupInputsEmitter.emit(hashID);
				}
			}
		} catch (error) {
			console.error("Error parsing group data:", error);
		}
	}
}

async function handleHostEvents(event) {
	// add
	// remove
	// rename
	// control/status change
	const parts = event.key.split('/');
	if (parts[0] !== "HOSTS") {
		// This shouldn't have gone to this handler
		return;
	}
	const hashID = parts[1];
	// Find Host with specific data-hash and data-type attributes
	let hostInstance = window.root.hosts.get(hashID);
	if (!hostInstance) {
		// the host neither exists in the dataset, nor in the DOM.
		// This is either an error, or it's a new host.
		// console.warn("Host instance not found! Potential failure mode, or New Host.");
		if (parts.length >= 3 && parts[2] === 'newHost') {
			// Check if this is a newHost event
			const shouldBeCreated = event.value === "newHost" ||
				event.value === "1" ||
				event.eventType === "PUT";
			if (shouldBeCreated) {
				console.info("Generating new host for hash:", hashID);
				// Fetch the host data and create the instance
				const response = await fetch("/get_keys.php", {
					method: "POST",
					headers: {"Content-Type": "application/json"},
				});
				if (!response.ok) throw new Error('Network response was not ok');
				const data = await response.json();
				const hostItem = data.hosts?.find(h => h.hashID === hashID);
				if (!hostItem) return;
				const hostData = {
					hashID: hostItem.hashID,
					ipAddress: hostItem.hostIP || "ERROR",
					hostType: hostItem.hostType,
					type: hostItem.type,
					controls: {
						label: hostItem.controls?.label || "UNKNOWN",
						blankStatus: hostItem.controls?.blankStatus || "0",
						rebootStatus: hostItem.controls?.rebootStatus || "0",
						resetStatus: hostItem.controls?.resetStatus || "0",
						revealStatus: hostItem.controls?.revealStatus || "0",
						healthStatus: hostItem.controls?.healthStatus || "OK",
						GROUP: hostItem.controls?.GROUP || null,
						directMode: hostItem.controls?.directMode ?? "1",
						UIEnable: hostItem.controls?.UIEnable ?? "0",
						screencastCapable: hostItem.controls?.screencastCapable ?? "0",
						promote: hostItem.controls?.promote ?? "0"
					}
				};
				const newHostInstance = new Host(hostData);
				window.root.hosts.set(hashID, newHostInstance);

				await createHostElement(newHostInstance);
				// Process inputs if available
				if (hostItem.inputs && Array.isArray(hostItem.inputs)) {
					hostItem.inputs.forEach(input => {
					const inputData = {
						hashID: input.hashID,
						keyFull: input.keyFull,
						labelText: input.labelText,
						type: "input",
						subType: input.subType || "net",
						hostHash: hashID,
						isActive: input.isActive || false,
						directMode: input.directMode ?? 1
					};
					const inputInstance = new Input(inputData);
					window.root.inputs.set(inputInstance.hashID, inputInstance);
					newHostInstance.registerHostInput(inputInstance);
					});
				}
				// Notify active group inputs emitter if needed
				const group = window.root.groups.get(newHostInstance.controls.GROUP);
				if (group && group.element) {
					group.updateActiveState();
				}
				// Consume the newHost flag
				void window.root.controlRequestManager.send({
					operation: "HOSTCONTROL",
					parentHash: newHostInstance.hashID,
					parentType: "host",
					controlKey: "hostCreated",
					controlValue: "YES",
					toggleOn: false
				});
			}
		}
	} else if (event.eventType === "DELETE") {
		// we only want to do this if the entire host prefix is removed
		// we do not want to delete the entire element on the removal of a single key
		if (parts.length >= 2) {
			console.warn(`Removing host ${hostInstance.controls?.label || 'Unknown'}`);
			hostInstance.unregisterHost(); // this should delete the host instance and remove its DOM element + inputs
		}
	} else {
		// Handle control update
		let controlName = parts.length > 3 ? parts[3] : null;
		try {
			// If hostInstance is null at this point, skip - likely still being created
			if (!hostInstance) {
				console.debug(`Skipping host control update (${controlName}) - host instance not yet created for ${hashID}`);
				return;
			}
			console.info("Host: " + hostInstance.controls.label + " Event for control: ", controlName);
			if (controlName in hostInstance.controls) {
				const currentValue = hostInstance.controls[controlName];
				if (String(currentValue) === String(event.value)) {
					console.log("Value hasn't changed for control", controlName);
					return;
				}
				const previousValue = currentValue;
				if (controlName === "healthStatus") {
					console.log("Host health event", event.value);
					hostInstance.controls.healthStatus = event.value;
					// Re-render the health indicator by removing old element and creating new one
					const parentElement = hostInstance.element;
					if (parentElement) {
						// Find the host-buttons container where health indicator resides
						const hostButtonsDiv = parentElement.querySelector('.host-buttons');
						if (hostButtonsDiv) {
							const existingHealthBox = hostButtonsDiv.querySelector(`#health-${hostInstance.hashID}`);
							if (existingHealthBox) {
								const newHealthBox = createHealthIndicator(hostInstance);
								hostButtonsDiv.replaceChild(newHealthBox, existingHealthBox);
							}
						}
					}
					return; // Exit early, we've handled it
				}
				hostInstance.controls[controlName] = event.value;
				console.log("Updated host control:", controlName, ", to:", event.value);
				if (hostInstance.emitter) {
					hostInstance.emitter.emit('controlUpdate', {
						controlName: controlName,
						newValue: event.value,
						oldValue: previousValue
					});
				}
				if (controlName === "GROUP") {
					hostInstance.changeGroup(event.value);
				}
				if (hostInstance.element) {
					hostInstance.element.classList.add('host-updated');
					requestAnimationFrame(() => {
						hostInstance.element.classList.remove('host-updated');
					});
				}
			} else {
				if (controlName !== "videoSource") {
					// noop, it's a silent key
					// console.log("silent control: ", controlName);
				}
			}
		} catch (error) {
			console.error("Error parsing host data:", error);
		}
	}
}

async function handleInputEvents(event) {
	// Inputs are created as a subcategory on a host, so they don't get created here.
	// activations are group level events
	console.log("Handling event for input event: ", event);
	let inputInstance = window.root.inputs.get(event.inputHash);
	if (event.eventType === "DELETE") {
		console.info("Deleting input device:", event.inputHash);
		// call the instance removal method which will destroy the instance
		if (inputInstance) {
			let host = window.root.hosts.get(inputInstance.hostHash);
			if (host) {
				host.unregisterInput(inputInstance);
			}
		}
	} else if (event.eventType === "UPDATE") {
		// the only other event type is "UPDATE" where we are creating or refreshing an instance
		console.info("Adding, or refreshing input device:", event.inputHash);
		if (!inputInstance) {
			console.info("Input not already generated, creating..");
			let parts = event.key.split('/');
			let hostHash = parts[1];
			let inputHash = parts[3];
			let valueParts = (event.value || '').split(';');
			let labelText = valueParts[1] || "Input " + inputHash.substring(0, 8);
			let subType = valueParts[4] || valueParts[3] || "net";
			try {
				// Check if host already exists in registry
				let hostInstance = window.root.hosts.get(hostHash);
				if (!hostInstance) {
					console.warn(`Host ${hostHash} not found, fetching from get_keys.php to create it...`);
					const response = await fetch("/get_keys.php", {
						method: "POST",
						headers: {"Content-Type": "application/json"},
					});
					if (!response.ok) {
						console.error('Network response was not ok while fetching host data');
						return;
					}
					const data = await response.json();
					const hostItem = data.hosts?.find(h => h.hashID === hostHash);
					if (!hostItem) {
						console.warn(`Host ${hostHash} still not found - skipping input creation`);
						return; // Only exit this function, not the whole try block prematurely
					}
					const hostData = {
						hashID: hostItem.hashID,
						ipAddress: hostItem.hostIP || "ERROR",
						hostType: hostItem.hostType,
						type: hostItem.type,
						controls: {
							label: hostItem.controls?.label || "UNKNOWN",
							blankStatus: hostItem.controls?.blankStatus || "0",
							rebootStatus: hostItem.controls?.rebootStatus || "0",
							resetStatus: hostItem.controls?.resetStatus || "0",
							revealStatus: hostItem.controls?.revealStatus || "0",
							healthStatus: hostItem.controls?.healthStatus || "OK",
							GROUP: hostItem.controls?.GROUP || null,
							directMode: hostItem.controls?.directMode ?? "1",
							UIEnable: hostItem.controls?.UIEnable ?? "0",
							screencastCapable: hostItem.controls?.screencastCapable ?? "0",
							promote: hostItem.controls?.promote ?? "0"
						}
					};
					hostInstance = new Host(hostData);
					window.root.hosts.set(hostHash, hostInstance);
				}
				// Create and register the input (only reached if we have a valid hostInstance)
				const newInputInstance = new Input({
					hashID: inputHash,
					keyFull: event.value,
					labelText: labelText,
					type: "input",
					subType: subType,
					hostHash: hostHash,
					isActive: false,
					directMode: hostInstance.controls?.directMode ?? "1"
				});
				window.root.inputs.set(inputHash, newInputInstance);
				hostInstance.registerHostInput(newInputInstance);
				if (hostInstance.element) {
					hostInstance.element.classList.add('host-updated');
					requestAnimationFrame(() => {
						hostInstance.element.classList.remove('host-updated');
					});
				}
			} catch (error) {
				console.error("Error creating input/host:", error);
			}
		} else {
			// Existing input updated - refresh its label text and state
			// Parse the value to extract input details
			let valuePartsUpdate = (event.value || '').split(';');
			let labelTextUpdate = valuePartsUpdate[1] || inputInstance.labelText;
			if (labelTextUpdate !== inputInstance.labelText) {
				inputInstance.labelText = labelTextUpdate;
				// Update DOM element text if it exists
				if (inputInstance.element) {
					let activateButton = inputInstance.element.querySelector('.btn__label');
					if (activateButton) {
						let textSpan = activateButton.querySelector('span');
						if (textSpan) {
							textSpan.textContent = labelTextUpdate;
							activateButton.dataset.label = labelTextUpdate;
						}
					}
				}
			}
		}
	}
}

function handleGlobalsEvents(event) {
	// console.log("Handling event for global event: ", event);
	// Effectively the only global controls we worry about are;
	// Advanced/Normal UI mode
	// Perhaps we may include some infra health status here in future
	const allGlobalsElements = document.querySelectorAll('[data-globals="true"]');
	let foundGlobalsElement = null;
	const lastPart = event.key.split('/').pop();
	allGlobalsElements.forEach(globalsElement => {
		// Changed to case-insensitive substring match
		if (globalsElement.id.toLowerCase().includes(lastPart.toLowerCase())) {
			console.log("Found affected globals element, setting status update!");
			// Only update value attribute, do NOT reload on toggle changes
			globalsElement.value = event.value;
			foundGlobalsElement = globalsElement;
			// IMPORTANT: Do NOT reload the page here!
			// The UI mode change should be applied dynamically via the UI state
			// If reload is truly needed, it should only happen once during an initial load
			// or be controlled by a specific reload flag.
		}
	});
	if (!foundGlobalsElement) {
		console.log("Element not found for globals event");
	}
}

function updateLastUpdateTime() {
	const updatesEl = document.getElementById('updates');
	if (updatesEl) {
		updatesEl.innerText = `Last update: ${new Date().toLocaleTimeString()}`;
		updatesEl.classList.remove('error');
	}
}

// Helper function to parse raw event data into structured objects
function parseEventToDataObject(event) {
	try {
		const parts = event.key.split('/');
		// Generalize to handle N parts regardless of input structure
		const eventData = {
			section: parts[0],
			itemHash: parts[1],
			category: parts[2], // "inputs" or "control" in host keys
			eventType: event.event_type || 'UNKNOWN',
			eventPrimitive: event.type || 'UNKNOWN',
			value: event.value,
			key: event.key,
			parts: parts,
			partsCount: parts.length
		};
		// Validate section
		if (eventData.section !== "GROUPS" &&
            eventData.section !== "HOSTS" &&
            eventData.section !== "HASH_ACTIVE" &&
            eventData.section !== "GLOBALS" &&
            eventData.section !== "INPUTS"
        ) {
			return null;
		}
		// Special handling for host-input relationship
		if (parts.length >= 4 && parts[2] === "inputs") {
			eventData.isInputEvent = true;
			if (eventData.section === "HOSTS") {
				eventData.section = "INPUTS";
			}
		}
		// Only set inputHash for actual input events (where category is "inputs")
		if (eventData.isInputEvent) {
			eventData.inputHash = parts[3];
		}
		return eventData;
	} catch (error) {
		console.error('Error parsing event:', error);
		return null;
	}
}

if (document.readyState === 'loading') {
	// Still loading, wait for DOMContentLoaded
	document.addEventListener('DOMContentLoaded', function () {
		void handlePageLoad();
	});
} else {
	// DOM is already loaded
	void handlePageLoad();
}