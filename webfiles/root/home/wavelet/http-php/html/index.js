var script = document.createElement('script');
script.src = './jquery-3.7.1.min.js';
document.getElementsByTagName('head')[0].appendChild(script);

var dynamicInputs = document.getElementById("dynamicInputs");
dynamicInputs.innerHTML = '';

function escapeHTML(val) {
	console.log("Escaping html for: " + val);
	let text 	=	val;
	let map = {
		'&': '&amp;',
		'<': '&lt;',
		'>': '&gt;',
		'"': '&quot;',
		"'": '&#039;'
	};
	return text.replace(/[&<>"']/g, function(m) {
		return map[m];
	});
}

function inputsAjax(){
// get dynamic devices from etcd, and call createInputButton function to generate entries for them.
// value = generated hash value of the device from detectv4l, this is how we track it, and how wavelet can find it
// keyfull = the pathname of the device in /UI/friendlyname
// key = the key of the device (also a UI-modifiable label attribute)
	var deferred = $.ajax({
		type: "POST",
		url: "get_inputs.php",
		dataType: "json",
	});

	deferred.done(function(returned_data) {
		counter = 3;
		console.log("JSON Inputs data received:");
		console.log(returned_data);
		returned_data.forEach(item => {
			const functionIndex =   1;
			var key			=	item['key'];
			var value		=	item['value'];
			var keyLong		=	item['keyLong'];
			var keyFull		=	item['keyFull'];
			var inputHost 	=	item['host'];
			var inputHostL	=	item['hostNamePretty'];
			createInputButton(key, value, keyLong, keyFull, inputHost, inputHostL, functionIndex);
			});
	});
	return deferred;
}


function hostsAjax(){
// get dynamic hosts from etcd, and call createNewHost to generate entries and buttons for them.
// returns:  Key (keyname), type (host type), hostName (hostname), hostHash (host's machine ID as SHA256sum), hostLabel (pretty hostname)
	var deferred = $.ajax({
		type: "POST",
		url: "get_hosts.php",
		dataType: "json",
	});
	deferred.done(function(returned_data) {
		counter = 500;
		console.log("JSON Hosts data received:");
		console.log(returned_data);
		returned_data.forEach(item => {
			const functionIndex	=	2;
			var key				=	item['key'];
			var type			=	item['type'];
			var hostName		=	item['hostName'];
			var hostHash		=	item['hostHash'];
			var hostLabel 		=	item['hostLabel'];
			var hostIP 			=	item['hostIP'];
			var hostBlankStatus	=   item['hostBlankStatus'];
			createNewHost(key, type, hostName, hostHash, hostLabel, hostIP, hostBlankStatus);
		});
	});
	return deferred;
}

function networkInputsAjax(){
// get dynamic network inputs from etcd, and call and generate entries and buttons for them.
	var deferred = $.ajax({
		type: "POST",
		url: "get_network_inputs.php",
		dataType: "json",
	});

	deferred.done(function(returned_data) {
		counter	=	3000;
		console.log("JSON Network Inputs data received:");
		console.log(returned_data);
		returned_data.forEach(item => {
			const functionIndex	=	3;
			var key				=	item['key'];
			var value			=	item['value'];
			var keyFull			=	item['keyFull'];
			var IPAddr			=	item['IP'];
			createInputButton(key, value, "network", keyFull, "network", "network", functionIndex, IPAddr);
		});
	});
	return deferred;
}

function sendPHPID(buttonElement) {
	// we use id here in place of value (both are same for static items in the html)
	// Because javascript inexplicably can access everythign EXCEPT the value??
	// Can probably retire this in favor of the dynamicPHPID function below.
	const postValue				=		(buttonElement.id);
	var postLabel				=		($(this).innerText);
	if (postLabel in window) {
		console.log("postLabel is not defined! Setting a dummy value..");
		var postLabel	=	"STATIC";
	}
	console.log("Sending Value: " + postValue + "\nAnd Label: " + postLabel);
	$.ajax({
		type: "POST",
			url: "/set_uv_hash_select.php",
			data: {
				value: postValue,
				label: postLabel
			},
			success: function(response){
				console.log(response);
				if (postValue == "RD" || "CL") {
					// Perhaps we also want to set the button inactive
					sleep(1250);
					location.reload();
				}
			}
	});
	var dynamicsArr				=		Array.from($('div[id="dynamic_inputs"] .btn'));
	//var dynamicsLclArr		=		Array.from($('div[id="dynamicInputs"] .btn'));
	//var dynamicsNetArr		=		Array.from($('div[id="dynamicNetworkInputs"] .btn'));
	var staticsArr				=		Array.from($('div[id="static_inputs_section"] .btn'));
	if (dynamicsArr.length > 0) {
		console.log("Found " + dynamicsArr.length + " sibling element(s).");
	} else {
		console.log("No elements found!");
	}
	for (const element of dynamicsArr) {
		if ($(element).hasClass ('renameButton removeButton')) {
		} else {
			console.log("Setting data-active to 0 for this Dynamic element ID:" + element);
			element.removeAttribute('data-active');
		}
	};			
	staticsArr.forEach((element, index) => {
		if ($(element).hasClass ('renameButton removeButton')) {
		} else {
			console.log("Setting data-active to 0 for this  Static element ID:" + element);
			element.removeAttribute('data-active');
			}
		});
	buttonElement.setAttribute("data-active", "1");
	console.log("Set data-active to 1 for " + buttonElement + "selected element");
}


function sendDynamicPHPID(buttonElement) {
	/* Sends via AJAX the button Value (Hash) and Label (shortname), then sets self as Active for CSS on page reload */
	/* Has to run a full DOM tree search to find itself though.. */
	const selectedDivHash                           =               $(this).parent().attr('divDeviceHash');
	const targetID									=               $(this).parent().attr('divDevID');
	const inputButtonKeyFull                        =               $(this).parent().attr('data-fulltext');
	const postValue									=				escapeHTML($(buttonElement).attr('value'))
	const postLabel									=				escapeHTML($(buttonElement).attr('label'));
	const keyNameFull								=				$(this).parent().attr('data-fulltext');
	const functionID								=				$(buttonElement).parent().attr('data-functionID');
	console.log("function ID is:" + functionID + "\npostLabel is: " + postLabel);
	if (functionID == 3) {
		setLabel= ("/network_interface/" + postLabel);
	} else {
		setLabel = postLabel;
	}
	console.log("Sending Value: " + postValue + "\nAnd Label: " + setLabel);
		$.ajax({
				type: "POST",
						url: "/set_uv_hash_select.php",
						data: {
								value: postValue,
								label: setLabel
								  },
						success: function(response){
								console.log(response);
						}
		});
		var dynamicsArr				=		Array.from($('div[id="dynamic_inputs"] .btn'));
		//var dynamicsLclArr		=		Array.from($('div[id="dynamicInputs"] .btn'));
		//var dynamicsNetArr		=		Array.from($('div[id="dynamicNetworkInputs"] .btn'));
		var staticsArr				=		Array.from($('div[id="static_inputs_section"] .btn'));
		if (dynamicsArr.length > 0) {
			console.log("Found " + dynamicsArr.length + " sibling element(s).");
		} else {
			console.log("No elements found!");
		}
			for (const element of dynamicsArr) {
					if ($(element).hasClass ('renameButton removeButton')) {
					} else {
						console.log("Setting data-active to 0 for this Dynamic element ID:" + element);
						element.removeAttribute('data-active');
						}
					};			
			staticsArr.forEach((element, index) => {
					if ($(element).hasClass ('renameButton removeButton')) {
					} else {
						console.log("Setting data-active to 0 for this  Static element ID:" + element);
						element.removeAttribute('data-active');
						}
			});
		buttonElement.setAttribute("data-active", "1");
		console.log("Set data-active to 1 for " + buttonElement + "selected element");
}


function handleButtonClick() {
	sendPHPID(this);
}

function handleDynamicButtonClick() {
	sendDynamicPHPID(this);
}

function togglebox_setup(toggleBox) {
	// adds appropriate event listener to the toggleBox, uses a common module to set the value
	let toggleID		=	toggleBox.split('_toggle_checkbox').join('');
	let toggleElementID =	$('#' + toggleBox);
	console.log("Adding event listener to ID: #" + toggleBox + "\nAnd key: " + toggleID);
	// 	$("#banner_toggle_checkbox").change 
	$(toggleElementID).on('change', function() {
		var checkbox = $(this)[0];
		if (checkbox.checked) {
			var toggleValue = 1;
		} else {
			var toggleValue = 0;
		}
		console.log("Submitting ID:" + toggleID + "\nValue: " + toggleValue);
		$.ajax({
			type: "POST",
			url: "/set_toggle_status.php",
			data: {
				toggleID:		toggleID,
				toggleValue:	toggleValue
				},
			success: function(response){
			console.log(response);
			}
		});
	});
}

function getToggleStatus(toggleKey, toggleValue) {
	// this function gets a toggle status and returns it.  Replaces audio, banner, livestream & persist toggle modules.
	console.log("Getting toggle value for /UI/" + toggleKey);
	$.ajax({
			type: "POST",
			url: "/get_toggle_status.php",
			data: {
				key: toggleKey
			},
		success: function(returned_data) {
		const toggleValue = JSON.parse(returned_data);
			if (toggleValue == "1" ) {
				console.log ( toggleKey + "value is 1, enabling toggle.");
				$("#" + toggleKey +"_toggle_checkbox")[0].checked=true;
				} else {
				console.log ("Banner value is 0, disabling toggle.");
				$("#" + toggleKey +"_toggle_checkbox")[0].checked=false;
				}
		}
	})
}

function handlePageLoad() {
	var livestreamValue				=		getToggleStatus("livestream", livestreamValue);
	var bannerValue					=		getToggleStatus("banner", bannerValue);
	var audioValue					=		getToggleStatus("audio", audioValue);
	var persistValue 				=		getToggleStatus("persist", persistValue);
	var bluetoothMACValue			=		getBluetoothMAC(bluetoothMACValue);
	// Adding classes and attributes to the prepopulated 'static' buttons on the webUI
	const staticInputElements		=		document.querySelectorAll(".btn");
	let toggleInputElements 		= 		Array.from(document.getElementsByClassName('toggle-checkbox'));
	var confirmElements 			= 		document.getElementsByClassName('serious');
	var confirmIt					= 		function (e) {
			var answer=confirm('Are you sure?');
			if(answer){
				alert('OK!');
			} else {
				e.preventDefault();
			}
		};
	for (var i = 0, l = confirmElements.length; i < l; i++) {
		confirmElements[i].addEventListener('click', confirmIt, false);
	}
	staticInputElements.forEach(el => 
		el.addEventListener("click", handleButtonClick));
	toggleInputElements.forEach(el => {
		togglebox_setup(el.id);
	});
	// Call AJAX to populate dynamic page areas
	inputsAjax().then(function() {
		hostsAjax();
	}).then(function() {
		networkInputsAjax();
	});
}

function pollAjax() {
	// This function runs an AJAX call from inputs, network inputs or hosts div.  That is 3x calls every 2s.
	// If the values returned differ from the previous variable, we call a full reconstruction of the target div.
	// because this approach is destructive, we do not need to worry about removing the device
	// as long as the poll value is changed as per the controller, the approach will work as desired.
	// we get back a packed value of timestamp|targetFunction
	// targetFunction is inputs, network inputs or hosts
	// normal console logging off here because otherwise it'll make using the console to debug impossible
	setTimeout(pollAjax, 5000);
	let oldPollValue	=	getCookie("oldPollValue");
	if (oldPollValue == "INIT") {
		console.log("Called with INIT value, page has just done loading");
	}
	//console.log("Attempting Poll!");
	$.ajax({
		type: "POST",
		url: "poll_etcd_key.php",
		dataType: "json",
	}).then(function(returned_data) {
		returned_data.forEach(item => {
			var pollKey			=	item['key'];
			var pollValue		=	item['value'];
			// console.log("Read key:" + pollKey + "For value: " + pollValue);
			if (pollValue == oldPollValue ) {
				//console.log ("The old and new poll values are identical, doing nothing.");
			} else {
				// trim the timestamp off to get the divider target
				dividerTarget		=	pollValue.substring(pollValue.indexOf("|") + 1);
				console.log ('Poll values have changed!  A system update has occurred somewhere, calling appropriate function ID:' + dividerTarget);
				setCookie("oldPollValue", pollValue);
				// can be:  net, inputs, hosts
				// put a case switcher;
				switch(dividerTarget) {
					case 'interface':
						console.log("Refresh inputs div");
						location.replace('#dynamic_inputs', inputsAjax());
					break;
					case 'network_interface':
						console.log("Refresh network inputs div");
						location.replace('#dynamicNetworkInputs', networkInputsAjax());
					break;
					case 'hosts':
						console.log("Refresh Hosts div");
						location.replace('#HostControlDiv', hostsAjax());
					break;
				}
			}
		});
	});
}

function getBluetoothMAC(bluetoothMACValue) {
	// this function gets the audio status from etcd and sets the audio toggle button on/off upon page load
	console.log ("Checking Bluetooth MAC..");
	$.ajax({
		type: "POST",
		url: "get_bluetooth_mac.php",
		dataType: "json",
		success: function(returned_data) {
			console.log("JSON data received:");
			console.log(returned_data);
			returned_data.forEach(item => {
				var btMACKey			=	item['key'];
				var bluetoothMACValue	=	item['value'];
				console.log("object key: " + btMACKey + " value: " + bluetoothMACValue);
				if (bluetoothMACValue == "" ) {
					console.log ("There is no value populated here, so we set the audio_toggle_checkbox to 0");
					$("#audio_toggle_checkbox")[0].checked=false; // set HTML checkbox to checked
				} else {
					console.log ('Audio value is NOT 0, pulling the value: ' + bluetoothMACValue + ' , and populating it into the text box');
					$("#btMAC").val(bluetoothMACValue); // set the value of the btMAC text box to the populated MAC address
				}
			})
		}
	})
}

function createHostButton(hostName, hostHash, item) {
/* add generic host button for controls */
	var $btn				=		$('<button/>', {
		type:   'button',
		text:   `${item} Host`,
		title:  `${item} Host`,
		value:  `${item}-${hostHash}`,      
		class:  'btn renameButton',
		id: 	`btn_Host-${hostHash}-${item}`,
		}).click(function(){
			console.log("Instructing host:" + hostName + "\nHash Value:" + hostHash + "\nTo Execute: " + item);
			$.ajax({
				type: "POST",
				url: "/set_host_control.php",
				data: {
					key:				hostName,
					hash:				hostHash,
					value:				"1",
					hostFunction:		item
					},
				success: function(response){
					console.log(response);
				}
			});
			// remove the UI element if this is a deprovision task
			if ( item == "DEPROVISION") {
				document.getElementById(this).parentElement.parentElement.remove();
			}
			sleep (750);
		})
	return $btn;
}

function createBlankButton(hostName, hostHash, hostBlankStatus) {
	// This function creates the host blank button, and changes the button text depending on status.
	var blankHostName			=		hostName;
	var blankHostHash			=		hostHash;
	var hostBlankStatus 		=		hostBlankStatus;
	var blankHostText			=		( hostBlankStatus ==="0") ? "Blank Host":"Unblank Host";

	console.log("Called to create Blank Host button for:" + hostName + ", hash " + hostHash + ", Blank status:" + hostBlankStatus );
	var $btn 					= 		$('<button/>', {
		type:					'button',
		text:					blankHostText,
		'data-blankHostName':   blankHostName,
		'data_hover':			'Blank Display',
		data_label:				`${blankHostText}`,
		class:					'btn',
		title:					'Set host to Blank Screen',
		id:						'btn_blank'
		}).click(function(){
			let matchedElement = $('body').find(`[data-blankHostName="${blankHostName}"]`);
			if ($(matchedElement).text() == "Blank Host") {
				console.log("Host instructed to blank screen with array:" + hostName);
				$.ajax({
					type: "POST",
					url: "/set_host_control.php",
					data: {
						key:			hostName,
						hash:			hostHash,
						value:			"1",
						hostFunction:	"BLANK"
						},
					success: function(response){
							console.log(response);
						}
				});
					console.log("Found element: " + matchedElement + ", setting to blanked status for UI..");
					$(matchedElement).text("Unblank Host");
					$(matchedElement).addClass('active');
			} else {
				console.log("Host instructed to restore display:" + hostName);
				$.ajax({
					type: "POST",
					url: "/set_host_control.php",
					data: {
						key:				hostName,
						hash:				hostHash,
						value:				"0",
						hostFunction:		"BLANK"
						},
					success: function(response){
						console.log(response);
					}
				});
				console.log("Found element: " + matchedElement + ", reverting to init state..");
				$(matchedElement).text("Blank Host");
				$(matchedElement).removeClass('active');
			}
		});
	return $btn;
}

function createCodecStateChangeButton(hostName, hostHash, type) {
	/* Add a button to set the codec state change for a host*/
	console.log("Called codec state change button with:" + hostName + "," +hostHash + "," + type);
	var buttonText					=		type;
		if (type == "dec"){
			buttonText = 'Enable Encoder';
		} else {
			buttonText = 'Enable Decoder';
		};
	var $btn = $('<button/>', {
		type:   'button',
		class:  'btn encoderButton',
		id: 	'btn_codec_swap',
		title:  'Change function',
		text:   buttonText
	});
		$btn.click(function(){
			console.log("Host instructed to switch codec functionality:" + hostName);
				$.ajax({
					type: "POST",
					url: "/set_host_control.php",
					data: {
						key:			hostName,
						hash:			hostHash,
						value:			"1",
						hostFunction:	"PROMOTE"
						},
				success: function(response){
					console.log(response);
					sleep (3000);
					location.reload()
				}
			});
		})
	return $btn;
}

function createDecoderMenuSet(hostName, hostHash, type) {
	console.log("Generating Decoder buttons in Hamburger Menu..");
	let activeMenuSelector			=	(`#hamburgerMenu_${hostHash}`);
	let buttonList 					=	['DEPROVISION','RESET','REBOOT','REVEAL'];
	for (let item of buttonList) {
		console.log("Setting up: " + item);
		$(activeMenuSelector).append(createHostButton(hostName, hostHash, item));
	}
	$(activeMenuSelector).append(createCodecStateChangeButton(hostName, hostHash, type));
}

function createEncoderMenuSet(hostName, hostHash, type) {
	console.log("Generating Encoder buttons in Hamburger Menu..");
	let activeMenuSelector			=	(`#hamburgerMenu_${hostHash}`);
	let buttonList 					=	['DEPROVISION','RESET','REBOOT','REVEAL'];
	for (let item of buttonList) {
				console.log("Setting up " + item);
		$(activeMenuSelector).append(createHostButton(hostName, hostHash, item));
	}
	$(activeMenuSelector).append(createCodecStateChangeButton(hostName, hostHash, type));
}

function createServerMenuSet(hostName, hostHash, type) {
	console.log("Generating Server buttons in Hamburger Menu..");
	let activeMenuSelector			=	(`#hamburgerMenu_${hostHash}`);
	let buttonList 					=	['RESET','REBOOT'];
	for (let item of buttonList) {
		console.log("Setting up " + item);
		$(activeMenuSelector).append(createHostButton(hostName, hostHash, item));
	}
}

function createDetailMenu(hostName, hostHash, type, divEntry) {
	/* Generates an HTML span for the hamburger menu */
	console.log("creating a detail menu element and populating with appropriate menu options for a:" + type)
	var hostMenuElement		=	$("<div>",	{
		class:	'hostMenuElement',
		id:	`hostMenuElement_${hostHash}`,
		type:	type
	}).appendTo(divEntry);
		var hostMenuElementInner	=       $("<div>",      {
				class:  'hostMenuElementInner',
				id:     `hostMenuElementInner_${hostHash}`,
		}).appendTo(hostMenuElement);
	var hamburgerLabel		=       $("<label>",    {
		for:	`openHostMenuID_${hostHash}`,
		class:	`hostMenuIconToggle hostMenuIconToggle_${hostHash}`
	});
	var hamburgerMenu               =       $("<div>",      {
		/* The actual Menu content, in our case - the host control button suite */
				class: `hostMenu hostMenu_${hostHash}`,
		id: `hamburgerMenu_${hostHash}`
	});
	var hamburgerMenuOverlay	=	$("<div>",	{
		class: 'hostMenuOverlay'
	});
		var hamburgerCheckBox           =       $("<input>",    {
				type:                   "radio",
		name:			"hostRadioCheck",
				class:                  "openHostMenuCheckbox openHostMenu",
				id:                     `openHostMenuID_${hostHash}`,
				attribute:              `data-hosthash=${hostHash}`
		}).on('click change', function () {
		$(this).prop('checked')//if checked
			? $(this).prop('checked',false).data('waschecked', false)//uncheck
		: $(this).prop('checked',true).data('waschecked', true)//else check
		.siblings('input[name="'+$(this).prop('name')+'"]').data('waschecked', false);//make siblings false
	});
	hamburgerCheckBox.appendTo(hostMenuElementInner);
	hamburgerLabel.appendTo(hostMenuElementInner);
	hamburgerMenu.appendTo(hostMenuElementInner);
	hamburgerLabel.append(
		`<div class="spinner diagonal part-1"></div>
		<div class="spinner horizontal"></div>
		<div class="spinner diagonal part-2"></div>`
	);
	hamburgerMenuOverlay.appendTo(hamburgerMenu);
	hostMenuElement.appendTo(divEntry);
	switch(type) {
		case 'dec':
			console.log("This is a decoder host, adding button set to hamburger menu\n");
			createDecoderMenuSet(hostName, hostHash, type, divEntry);
			break;
		case 'enc':
			console.log("This is an encoder host");
			createEncoderMenuSet(hostName, hostHash, type, divEntry);
			break;
		case 'svr':
			console.log("This is a Server");
			createServerMenuSet(hostName, hostHash);
			break;
	}
}

function ajaxMonitor(hash) {
	// Takes the hash argument and tries to return a status every .5 seconds from the parent div hash
	const selectedDivHash				=		$(this).parent().attr('divDeviceHash');
	var interval = 500;  // 1000 = 1 second, 3000 = 3 seconds
		function doAjax() {
    		$.ajax({
	            type: 'POST',
            	url: '/get_device_status.php',
            	data: {
					hash:			selectedDivHash
            	},
            	dataType: 'json',
            	success: function (data) {
                    	$('#hidden').val(data);// first set the value     
            	},
            	complete: function (data) {
                    	// Schedule the next
                    	setTimeout(doAjax, interval);
            	}
    		});
	}
	setTimeout(doAjax, interval);
}

function checkForDuplicate(divLoc, divAttr, value) {
	// Look for duplicates
	// console.log("Looking for duplicate entries for hash: " + value + "\nIn parent Div: " + divLoc + "\nFor Attribute: " + divAttr);
	const divID							=		document.getElementById(divLoc);
	const childNodes					=		Array.from(divID.getElementsByTagName("*"));
	let liveChildElements				=		childNodes.filter((node) => node.nodeType === Node.ELEMENT_NODE);
	let duplicateEntryFound				=		false;
	liveChildElements.forEach((element) => {
		const foundDivHash = element.getAttribute(divAttr);
		if ( foundDivHash == value ) {
			// here we need to check if anything about this duplicate changed
			duplicateEntryFound 		= 		true;
		} else {
			// console.log("No entry discovered for value: " + value);
		}
	});
	return duplicateEntryFound;
}

function createInputButton(key, value, keyLong, keyFull, inputHost, inputHostL, functionIndex, IP) {
	// Note that for the frontend, we always use the PRETTY hostname set for the client
	// the "real" hostname is still saved as a data attr, but not really used here.
	var divEntry						=		document.createElement("Div");
	var dynamicButton					=		document.createElement("Button");
	const text							=		document.createTextNode(key);
	const id							=		document.createTextNode(counter + 1);
	dynamicButton.id					=		counter;
	hostName							=		inputHost;
 	hostNameLabel						=		inputHostL;
	deviceLabel							=		key;
	fullKey 							=		keyFull;

	/* create a div container, where the button, relabel button and any other associated elements reside */
	if (functionIndex === 1) {
		console.log("called from firstAjax, so this is a local video source");
		if (checkForDuplicate("dynamicInputs", "divDeviceHash", value)) {
			return;
		}
		dynamicInputs.appendChild(divEntry);
		divEntry.setAttribute("data-functionID", functionIndex);
		const title						=		document.createTextNode(key);
		hostNameAndDevice				=		(hostNameLabel + ":" + key);
	} else if (functionIndex === 3) {
		console.log("called from thirdAjax, so this is a network video source");
		if (checkForDuplicate("dynamicNetworkInputs", "divDeviceHash", value)) {
			return;
		}
		hostNameAndDevice				=		(IP + ":" + key);
		dynamicNetworkInputs.appendChild(divEntry);
		divEntry.setAttribute("divDeviceHash", functionIndex);
		divEntry.setAttribute("title", IP);
		$('#dynamicNetworkInputs').addClass('dynamicNetworkInputs');
	} else {
		console.error("createInputButton not called from a valid function");
	}
	var currentInputsHash				=		getActiveInputHash();
	divEntry.setAttribute("divDeviceHash", value);
	divEntry.setAttribute("data-fulltext", fullKey);
	divEntry.setAttribute("data-label", hostNameLabel + ":" + key);
	divEntry.setAttribute("data-inputHost", hostName);
	divEntry.setAttribute("data-inputHostLabel", hostNameLabel);
	divEntry.setAttribute("divDevID", dynamicButton.id);
	$(divEntry).addClass('input_divider_device');
	console.log("dynamic video source div created for device hash: " + value + " and label:  " + key + "on host: " + hostName);
	// Create the device button
	function createInputButton(text, value) {
		var $btn = $('<button/>', {
			type:	'button',
			text:	hostNameAndDevice,
			label:	key,
			value:	value,
			class:	'btn',
			title:	'Select this input',
			id:		dynamicButton.id,
			func:	$(this).parent().attr('data-functionID')
		}).click(handleDynamicButtonClick);
		$btn.data("fulltext", keyFull);
		return $btn;
	}
	//  Create a rename button
	function createRenameButton() {
		var $btn = $('<button/>', {
			type:	'button',
			text:	'Rename',
			class:	'btn renameButton',
			title:	'Relabel this item',
			id:		'btn_rename',
			func:	$(this).parent().attr('data-functionID')
			}).click(relabelInputElement);
		$btn.data("fulltext", keyFull);
		return $btn;
	}
	//  Create a remove button
	function createInputDeleteButton() {
		var $btn = $('<button/>', {
			type:	'button',
			text:	'Remove',
			title:	'Delete this entry',
			class:	'btn removeButton',
			id:		'btn_delete',
			func:	$(this).parent().attr('data-functionID')
		}).click(removeInputElement);
		return $btn;
	}
	$(divEntry).append(createInputDeleteButton());
	$(divEntry).append(createRenameButton());
	$(divEntry).append(createInputButton(text, value));
	var createdButton 					= 		$(divEntry).find('.dynamicInputButton');
	const selectedDivHash				=		$(this).parent().attr('divDeviceHash');
	counter++;
}

function checkHostDuplicate(type, hostHash) {
	// called AFTER we check for duplicates initially, and only if the hash IS a duplicate
	console.log("Looking for hostHash: " +hostHash+ "\nwith type: " +type);
	let update 							=		false;
	const divLoc						=		"HostControlDiv";
	const divID							=		document.getElementById(divLoc);
	const childNodes					=		Array.from(divID.getElementsByTagName("*"));
	let liveChildElements				=		childNodes.filter((node) => node.nodeType === Node.ELEMENT_NODE);
	liveChildElements.forEach((element) => {
		let elementHash  				=		element.getAttribute("divhost");
		let elementClass				=		element.getAttribute("class");
		if ( hostHash == elementHash && elementClass == "host_divider") {
			let elementType 			= 		element.getAttribute("data-hosttype");
			console.log("Host Type is: " + elementType)
			if ( type == elementType) {
				console.log("Type unchanged.")
			} else {
				let update				=	true;
				element.remove();
			}
		}
	});
	return update;
}

function createNewHost(key, type, hostName, hostHash, hostLabel, hostIP, hostBlankStatus, functionIndex) {
	let update							=		false;
	var divEntry						=		document.createElement("Div");
	var type							=		type;
	const id							=		document.createTextNode(counter + 1);
	var hostBlankStatus					=		hostBlankStatus;
	divEntry.setAttribute("id", id);
	divEntry.setAttribute("divHost", hostHash);
	divEntry.setAttribute("data-fulltext", key);
	divEntry.setAttribute("data-hostName", hostName);
	divEntry.setAttribute("data-hostType", type);
	divEntry.setAttribute("title", "IP: " + hostIP);
	$(divEntry).addClass('host_divider');
	// am I a duplicate?
	if (checkForDuplicate("HostControlDiv", "divhost", hostHash)) {
		console.log("Working on a duplicate, applying type test..");
		if(checkHostDuplicate(type, hostHash)) {
			console.log("element should now be deleted.");
		} else {
			return;
		}
	} else {
			console.log("unique ID, continuing");
	}
	/* This needs to be done "backwards" insofar as the type needs to be determined before we can start creating a new DIV */
	console.log("Generating label and buttons with\nHost Label: "+hostLabel+"\nHost Name: "+hostName+"\nAnd Host Hash: "+hostHash+"\nAnd type: "+type+"\nAnd IP: "+hostIP+"\nAnd blank status: "+hostBlankStatus);
	function createClientButtonSet(hostLabel, hostName, hostHash, type){
		var labelTextBox					=		document.createElement("input");
		var labelTextBoxLabel				=		document.createElement("label");
		labelTextBox.innerHTML 				=		hostLabel;
		labelTextBox.setAttribute("type", "text");
		labelTextBox.setAttribute("value", hostLabel);
		labelTextBox.setAttribute("data-hostHash", hostHash);
		labelTextBox.setAttribute("class", "input_textbox, hostTextBox");
		labelTextBox.id=("labelTextBox"+hostHash);
		labelTextBox.addEventListener('focus', function() {
			var oldLabelValue 	= $(this).attr("value");	
			console.log('picking up button value of ' +oldLabelValue);
		});	
		labelTextBox.addEventListener('blur', function() {
			var oldLabelValue				=		$(this).attr("value");
			var prettyName					=		$(this).val();
			var phpHostHash					=		$(this).attr("data-hostHash");
			if ( oldLabelValue 				==		prettyName ) {
				console.log("Error, values have not changed, doing nothing")
			} else {
			console.log("submitting to set_host_control.php with values---\nHash: " + phpHostHash + "\nNew Label: " + prettyName + "\nHostname: " + hostName + "\nType: " + type);
			$.ajax({
				url : '/set_host_control.php',
				type :'post',
				data:{
					hash:			phpHostHash,
					value:			prettyName,
					key:			hostName,
					type   :		type,
					hostFunction:	"label"
					},
				success:	function(response) {
					console.log(response);
				}
			});
		}});
		$(divEntry).append(labelTextBox);
		$(divEntry).append(createBlankButton(hostName, hostHash, hostBlankStatus));
		$(divEntry).append(createDetailMenu(hostName, hostHash, type, divEntry));
		counter ++;
	}
	function createServerButtonSet(hostName, hostHash){
		(divEntry).append("Host:" + hostName);
		console.log("Generating Server label and buttons.");
		$(divEntry).append(createDetailMenu(hostName, hostHash, type, divEntry));
	}
	function createGatewayButtonSet(hostName, hostHash){
	}
	function createLivestreamButtonSet(hostName, hostHash){
	}
	switch(type) {
		case 'dec':
			let dynamicdecHosts = document.getElementById('dynamicdecHosts');
			console.log("This is a decoder host");
			dynamicdecHosts.appendChild(divEntry);
			createClientButtonSet(hostLabel, hostName, hostHash, type);
			counter++;
			break;
		case 'enc':
			let dynamicencHosts = document.getElementById('dynamicencHosts');
			console.log("This is an encoder host");
			dynamicencHosts.appendChild(divEntry);
			createClientButtonSet(hostLabel, hostName, hostHash, type);
			counter++;
			break;
		case 'svr':
			console.log("This is a Server");
			dynamicsvrHosts.appendChild(divEntry);
			createServerButtonSet(hostName, hostHash);
			break;
	}
}

function relabelInputElement() {
	const selectedDivHash							=				$(this).parent().attr('divDeviceHash');
	const relabelTarget								=				$(this).parent().attr('divDevID');
	const fullLabel									=				$(this).parent().attr('data-fulltext');
	var newTextInput								=				prompt("Enter new text label for this device:", "New Label Value.");
	const inputButtonLabel							=				$(this).next('button').attr('label');
	var hostName									=				$(this).parent().attr('data-inputHost');
	var hostLabel									=				$(this).parent().attr('data-inputHostLabel');
	const functionID								=				$(this).parent().attr('data-functionID');
	var deviceIpAddr								=				$(this).parent().attr('title');
	console.log("Found Hash is: " + selectedDivHash + "\nFound button ID is: " + relabelTarget + "\nFound old label is: " + inputButtonLabel);
	console.log("Device full label is: " + fullLabel);
	if (functionID == 3) {
		hashValue	=	selectedDivHash;
		hostName	=	`${deviceIpAddr}`;
		hostLabel	=	`${deviceIpAddr}`;
		console.log('This is a network device!\nSetting hostname to: ' + deviceIpAddr + ":" + newTextInput);
	} else {
		console.log('This is a local device, use div hash');
		hashValue	=	selectedDivHash;
		inputButtonLabel;
		console.log("New device label will be hostLabel +: " + newTextInput + "\non Hostname: " + hostName);
	}
	if (newTextInput !== null && newTextInput !== "") {
		document.getElementById(relabelTarget).innerText = `${hostLabel}:${newTextInput}`;
		console.log("Button text successfully applied as: " + hostLabel + ":" + newTextInput + ", for system host: " + hostName );
		console.log("The originally generated device field from Wavelet was: " + fullLabel);
		console.log("The button must be activated for any changes to reflect on the video banner (if it is on)");
		$.ajax({
			type: "POST",
			url: "/set_input_label.php",
			data: {
				// Remember we are regenerating the full packed data so we need everything
				host:				hostName, 
				hostLabel:			hostLabel,			
				value:				hashValue,
				label:				newTextInput,
				oldInterfaceKey:	fullLabel,
			  },
			success: function(response){
				console.log(response);
			}
			});
	} else {
		console.log("text input was empty!");
		return;
	}
}

function removeInputElement() {
	const selectedDivHash                           =               $(this).parent().attr('divDeviceHash');
	const relabelTarget                             =               $(this).parent().attr('divDevID');
	const inputButtonKeyFull                        =               $(this).parent().attr('data-fulltext');
	const functionID								=				$(this).parent().attr('data-functionID');
	console.log("Found Hash for removal is: " + selectedDivHash + "\nFound button ID is: " + relabelTarget + "\nFound Label is: " + inputButtonKeyFull);
	hashValue = selectedDivHash;
	console.log("Deleting input entry and associated key: " + inputButtonKeyFull + " and value: " + hashValue);
		$.ajax({
			type: "POST",
			url: "/set_remove_input.php",
			data: {
				key: inputButtonKeyFull,
				value: hashValue
			},
			success: function(response){
				console.log(response);
			}
		});
	$(this).parent().remove();
}

function removeHostElement(hostName, hostHash) {
	console.log("Host Name for removal is: " + hostName + "\nHash is: " + hostHash);
		$.ajax({
			type: "POST",
			url: "/set_remove_host.php",
			data: {
				key: hostName,
				value: hostHash
			},
			success: function(response){
				console.log(response);
			}
		});
	$(this).parent().remove();
	sleep(1000);
	location.reload();
}

function setButtonActiveStyle(button) {
	$(this).removeClass('active');
		$(this).addClass('active');
}

function applyLivestreamSettings() {
	postValue	=	(this.value);
	var vlsurl	=	$("#lsurl").val();
	var vapikey	=	$("#lsapikey").val();
	$.ajax({
		type: "POST",
		url: "/set_apply_livestream.php",
		data: {
			lsurl: vlsurl,
			apikey: vapikey
			},
		success: function(response){
			console.log(response);
		}
	});
}

function applyAudioBlueToothSettings() {
	postValue	=	(this.value);
	var btMACValue = $("#btMAC").val();
	console.log("Bluetooth MAC is: " + btMACValue);
	$.ajax({
		type: "POST",
		url: "/set_bluetooth_mac.php",
		data: {
			key: 'audio_interface_bluetooth_mac',
			btMAC: btMACValue
		},
		success: function(response){
			console.log(response);
		}
	});
}

function getActiveInputHash(activeInputHash) {
	let returned_data;
	var key		=	"";
	var value	=	"";
		$.ajax({
			type: "POST",
			url: "get_uv_hash_select.php",
			dataType: "json",
			success: function(returned_data) {
				console.log(returned_data);
				returned_data.forEach(item => {
					key				=	item['key'];
					value			=	item['value'];
				});
				var activeInputHash	=	value; 
				console.log("Attempting to find a button with input hash value of: " + activeInputHash);
				$(".btn").each(function() {
					if ($(this).attr('value') && $(this).attr('value').trim() === activeInputHash) { 
						console.log("Found button with input hash: " + activeInputHash + ", setting as active for CSS..");
						if ( activeInputHash == "RD") {
							console.log("input source refresh is the selected hash, doing nothing..")
						} else {
						this.setAttribute("data-active", "1");
						}
					} else {
						//console.log("No button with value: " + activeInputHash + " found.");
					}
				});
			},
			error: function (xhr, ajaxOptions, thrownError) {
				console.log(thrownError);
			}
		}).then();
}

function sleep(ms) {
	console.log("Sleeping for:" + ms);
	return new Promise(resolve => setTimeout(resolve, ms || DEF_DELAY));
}

function setCookie(cname, cvalue, exdays) {
  const d = new Date();
  d.setTime(d.getTime() + (exdays * 24 * 60 * 60 * 1000));
  let expires = "expires="+d.toUTCString();
  document.cookie = cname + "=" + cvalue + ";" + expires + ";path=/";
}

function getCookie(cname) {
  let name = cname + "=";
  let ca = document.cookie.split(';');
  for(let i = 0; i < ca.length; i++) {
    let c = ca[i];
    while (c.charAt(0) == ' ') {
      c = c.substring(1);
    }
    if (c.indexOf(name) == 0) {
      return c.substring(name.length, c.length);
    }
  }
  return "";
}

const callingFunction = (callback) => {
	const callerId = 'calling_function';
	callback(this);
}

$(document).ready(function() {
	getActiveInputHash("your_input_hash");
	console.log("Setting up AJAX polling for events..");
	setCookie("oldPollValue", "INIT", 365);
	setTimeout(pollAjax, 3000);
});