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
// keyfull = the pathname of the device in /interface/friendlyname
// key = the key of the device (also a UI-modifiable label attribute)
	$.ajax({
		type: "POST",
		url: "get_inputs.php",
		dataType: "json",
		success: function(returned_data) {
			counter = 3;
			console.log("JSON Inputs data received:");
			console.log(returned_data);
			returned_data.forEach(item => {
				const functionIndex =   1;
				var key			=	item['key'];
				var value		=	item['value'];
				var keyFull		=	item['keyFull'];
				createInputButton(key, value, keyFull, functionIndex);
				})
		},
		complete: function(){
			hostsAjax();
		}
	});
}

function hostsAjax(){
// get dynamic hosts from etcd, and call createNewHost to generate entries and buttons for them.
// returns:  Key (keyname), type (host type), hostName (hostname), hostHash (host's machine ID as SHA256sum), hostLabel (pretty hostname)
	$.ajax({
		type: "POST",
		url: "get_hosts.php",
		dataType: "json",
		success: function(returned_data) {
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
				var blankstatus  	=   item['hostBlankStatus'];
				createNewHost(key, type, hostName, hostHash, hostLabel, hostIP, blankstatus);
				})
		},
	complete: function(){
		networkInputsAjax();
	}
	});
}

function networkInputsAjax(){
// get dynamic network inputs from etcd, and call and generate entries and buttons for them.
// why aren't we moving to Angular/REACT already? oh that's right.. i haven't had time to learn it yet..
	$.ajax({
		type: "POST",
		url: "get_network_inputs.php",
		dataType: "json",
		success: function(returned_data) {
			counter	=	3000;
			console.log("JSON Network Inputs data received:");
			console.log(returned_data);
			returned_data.forEach(item => {
				const functionIndex	=	3;
				var key				=	item['key'];
				var value			=	item['value'];
				var keyFull			=	item['keyFull'];
				var IPAddr			=	item['IP'];
				createInputButton(key, value, keyFull, functionIndex, IPAddr);
			})
		},
	});
}

function fetchHostLabelAndUpdateUI(getLabelHostName){
	// This function gets hostname | label from etcd and is responsible for telling the server which text labels to produce for each host.
	// We should probably fold this into get_hosts.php so it is provided at once.
	$.ajax({
		type: "POST",
		url: "get_host_label.php",
		dataType: "json",
		success: function(returned_data) {
			counter = 500;
			console.log("JSON Hosts data received:");
			console.log(returned_data);
			returned_data.forEach(item, index => {
				var key	=	item['key'];
			})
		}
	});

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
	console.log("Getting toggle value for /ui/" + toggleKey);
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
	// Execute initial AJAX Call
	inputsAjax();
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
			console.log("Instructing host:" + hostName + "\nHash Value:" + hostHash + "\nTo: " + item);
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
			})
			sleep (750);
			location.reload();
		})
	return $btn;
}

function getBlankHostStatus(hostName, hostHash) {
	// this function gets the host blank bit status, and then sets the button text based on that value
	console.log('Attempting to get host blank bit for: ' + hostName + ", hash:" +hostHash);
	let retValue = null;
	var blankHostName = hostName;
	$.ajax({
		type: "POST",
		url: "get_blank_host_status.php",
		dataType: "json",
		data: {
			key: hostName
		},
		success: function(returned_data) {
			console.log("Returned blank bit value for " + hostName +" is: " + returned_data);
			if (returned_data == "1") {
				console.log("Value is " + returned_data + ", changing CSS and text appropriately");
				let matchedElement = $('body').find(`[data-blankHostName="${blankHostName}"]`);
				if(matchedElement){
					console.log("Found element: " + matchedElement);
					$(matchedElement).text("Unblank Host");
					$(matchedElement).addClass('active');
						return true;
				} else {
					console.log("Could not find the element with this selector!");
				}
			} else if (returned_data == "0") {
								let matchedElement =
								$('body').find(`[data-blankHostName="${blankHostName}"]`);
								$(matchedElement).text("Blank Host");
								$(matchedElement).removeClass('active');
			} else {
				console.log("invalid bit returned!")
			};
		}
	});
}

function createBlankButton(hostName, hostHash, initialHostBlankStatus) {
	// This function creates the host blank button, and changes the button text depending on status.
	var blankHostName			=		hostName;
	var blankHostHash			=		hostHash;
	var blankHostText			=		"pending status";
	console.log("Called to create Blank Host button for:" + hostName + ", hash " + hostHash );
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
				console.log("Host instructed to blank screen:" + blankHostName);
				$.ajax({
					type: "POST",
					url: "/set_host_control.php",
					data: {
					key:				hostName,
					hash:				hostHash,
					value:				"1",
					hostFunction:		"BLANK"
						},
						success: function(response){
							console.log(response);
						}
				});
					console.log("Found element: " + matchedElement + ", setting to blanked status for UI..");
					$(matchedElement).text("Unblank Host");
					$(matchedElement).addClass('active');
			} else {
				console.log("Host instructed to restore display:" + blankHostName);
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
						key:				hostName,
						hash:				hostHash,
						value:				"1",
						hostFunction:		"PROMOTE"
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
		console.log("Setting up" + item);
		$(activeMenuSelector).append(createHostButton(hostName, hostHash, item));
	}
	$(activeMenuSelector).append(createCodecStateChangeButton(hostName, hostHash, type));
}

function createEncoderMenuSet(hostName, hostHash, type) {
	console.log("Generating Decoder buttons in Hamburger Menu..");
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

function createInputButton(key, value, keyFull, functionIndex, IP) {
	var divEntry					=		document.createElement("Div");
	var dynamicButton				=		document.createElement("Button");
	const text						=		document.createTextNode(key);
	const id						=		document.createTextNode(counter + 1);
	dynamicButton.id				=		counter;
	hostNameAndDevice				=		key.replace(/\//, ':\n');
	/* create a div container, where the button, relabel button and any other associated elements reside */
	if (functionIndex === 1) {
		console.log("called from firstAjax, so this is a local video source");
		dynamicInputs.appendChild(divEntry);
		divEntry.setAttribute("data-functionID", functionIndex);
		const title						=		document.createTextNode(key);
	} else if (functionIndex === 3) {
		console.log("called from thirdAjax, so this is a network video source");
		hostNameAndDevice			=		(IP + ": " + key);
		dynamicNetworkInputs.appendChild(divEntry);
		divEntry.setAttribute("data-functionID", functionIndex);
		divEntry.setAttribute("title", IP);
		$('#dynamicNetworkInputs').addClass('dynamicNetworkInputs');
	} else {
		console.error("createInputButton not called from a valid function");
	}
	var currentInputsHash			=		getActiveInputHash();
	
	divEntry.setAttribute("divDeviceHash", value);
	divEntry.setAttribute("data-fulltext", keyFull);
	divEntry.setAttribute("divDevID", dynamicButton.id);
	$(divEntry).addClass('input_divider_device');
	console.log("dynamic video source div created for device hash: " + value + " and label:  " + key);
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
	var createdButton = $(divEntry).find('.dynamicInputButton');
	/* We might as well do this on pageload instead of creating the buttons..
	 * 
	 * if (createdButton.val() == currentInput) {
		console.log("This button is the currently selected input hash, changing CSS to active!");
		$(createdButton.css({
			'background-color': 'red',
			'color': 'white',
			'font-size': '44px'
		}));
	} */

	/* set counter +1 for button ID */
	const selectedDivHash			=		$(this).parent().attr('divDeviceHash');
	counter++;
}

function createNewHost(key, type, hostName, hostHash, hostLabel, hostIP, blankstatus, functionIndex) {
	var divEntry						=		document.createElement("Div");
	var type							=		type;
	const id							=		document.createTextNode(counter + 1);
	var initialHostBlankStatus			=		getBlankHostStatus(hostName, hostHash);
	divEntry.setAttribute("id", id);
	divEntry.setAttribute("divHost", hostHash);
	divEntry.setAttribute("data-fulltext", key);
	divEntry.setAttribute("data-hostName", hostName);
	divEntry.setAttribute("data-hostType", type);
	divEntry.setAttribute("title", "IP: " + hostIP);
	$(divEntry).addClass('host_divider');

	/* This needs to be done "backwards" insofar as the type needs to be determined before we can start creating a new DIV */
	console.log("Generating label and buttons with\nHost Label: "+hostLabel+"\nHost Name: "+hostName+"\nAnd Host Hash: "+hostHash+"\nAnd type: "+type+"\nAnd IP: "+hostIP);
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
			console.log("submitting to set_hostlabel.php with values---\nHash: " + phpHostHash + "\nNew Label: " + prettyName + "\nHostname: " + hostName + "\nType: " + type);
			$.ajax({
				url : '/set_host_label.php',
				type :'post',
				data:{
					hash:			phpHostHash,
					prettyName:		prettyName,
					hostName:		hostName,
					type   :		type
					},
				success:	function(response) {
					console.log(response);
				}
			});
		}});
		$(divEntry).append(labelTextBox);
		$(divEntry).append(createBlankButton(hostName, hostHash, blankstatus));
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
	const selectedDivHash                           =               $(this).parent().attr('divDeviceHash');
	const relabelTarget                             =               $(this).parent().attr('divDevID');
	const oldGenText                                =               $(this).parent().attr('data-fulltext');
	const newTextInput                              =               prompt("Enter new text label for this device:");
	const inputButtonLabel                          =               $(this).next('button').attr('label');
	var hostName									=               $(this).next('button').attr('label').split('/')[0];
	const functionID								=				$(this).parent().attr('data-functionID');
	var deviceIpAddr								=				$(this).parent().attr('title');
	console.log("Found Hash is: " + selectedDivHash + "\nFound button ID is: " + relabelTarget + "\nFound Label is: " + inputButtonLabel);
	console.log("Device full label is: " + oldGenText + "\nNew device label: " + newTextInput + "\nHostname: " + hostName);
	if (functionID == 3) {
		hashValue	= ("/network_interface/" + selectedDivHash);
		hostName	= `${deviceIpAddr}`;
		console.log('This is a network device, substituting path strings for PHP handler\nSetting hostname to IP Address:' + deviceIpAddr);
	} else {
		hashValue = selectedDivHash;
	}
	if (newTextInput !== null && newTextInput !== "") {
		document.getElementById(relabelTarget).innerText = `${hostName}: ${newTextInput}`;
		document.getElementById(relabelTarget).oldGenText = oldGenText;
		console.log("Button text successfully applied as: " + hostName + newTextInput);
		console.log("The originally generated device field from Wavelet was: " + oldGenText);
		console.log("The button must be activated for any changes to reflect on the video banner!");
		$.ajax({
			type: "POST",
			url: "/set_input_label.php",
			data: {
				value:          hashValue,
				label:          (hostName + "/" + newTextInput),
				oldvl:          oldGenText,
				hostName:       hostName
			  },
			success: function(response){
				console.log(response);
			}
			});
	} else {
		return;
	}
}

function removeInputElement() {
	const selectedDivHash                           =               $(this).parent().attr('divDeviceHash');
	const relabelTarget                             =               $(this).parent().attr('divDevID');
	const inputButtonKeyFull                        =               $(this).parent().attr('data-fulltext');
	const functionID								=				$(this).parent().attr('data-functionID');
	console.log("Found Hash for removal is: " + selectedDivHash + "\nFound button ID is: " + relabelTarget + "\nFound Label is: " + inputButtonKeyFull);
	if (functionID == 3) {
		console.log("Network device, function ID 3");
		hashValue = ("/network_ip/" + selectedDivHash);
	} else {
		console.log("Local device or other, function ID not 3");
		hashValue = selectedDivHash;
	}
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
	sleep(300);
	location.reload();
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
	sleep(300);
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
	return new Promise(resolve => setTimeout(resolve, ms || DEF_DELAY));
}

const callingFunction = (callback) => {
	const callerId = 'calling_function';
	callback(this);
};

$(document).ready(function() {
	getActiveInputHash("your_input_hash");
});