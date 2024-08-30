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
// value = generated hash value of the device, this is how we track it, and how wavelet can find it
// keyfull = the pathname of the device in /interface/friendlyname
// key = the key of the device (also friendlyname)
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
// returns:  Key (keyname), type (host type), and makes one further call to get the host's hash value
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
				createNewHost(key, type, hostName, hostHash);
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
		const postValue				=		(buttonElement.id);
		const postLabel				=		($(this).innerText);
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
									setTimeout(() => window.location.reload(), 750);
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


function handlePageLoad() {
	var livestreamValue				=		getLivestreamStatus(livestreamValue);
	var bannerValue					=		getBannerStatus(bannerValue);
	var audioValue					=		getAudioStatus(audioValue);
	var bluetoothMACValue			=		getBluetoothMAC(bluetoothMACValue);
	var audioStatus					=		getAudioStatus(audioValue);
	// Adding classes and attributes to the prepopulated 'static' buttons on the webUI
	const staticInputElements		=		document.querySelectorAll(".btn");
	var confirmElements = document.getElementsByClassName('serious');
    
    var confirmIt = function (e) {
        if (!confirm('Are you sure?')) e.preventDefault();
    };
    for (var i = 0, l = confirmElements.length; i < l; i++) {
        confirmElements[i].addEventListener('click', confirmIt, false);
    }

	staticInputElements.forEach(el => 
		el.addEventListener("click", handleButtonClick));
	// Apply event listener to Livestream toggle
	$("#lstoggleinput").change
		(function() {
			if ($(this).is(':checked')) {
				$.ajax({
					type: "POST",
					url: "/set_enable_livestream.php",
					data: {
						lsonoff: "1"
						},
					success: function(response){
					console.log(response);
					}
				});
				} else {
					$.ajax({
						type: "POST",
						url: "/set_enable_livestream.php",
						data: {
								lsonoff: "0"
								},
								success: function(response){
								console.log(response);
								}
							});

				}
	});
	// Apply event listener to banner toggle
	$("#banner_toggle_checkbox").change
		(function() {
			if ($(this).is(':checked')) {
				$.ajax({
					type: "POST",
					url: "/set_enable_banner.php",
					data: {
						banneronoff: "1"
					},
					success: function(response){
						console.log(response);
					}
				});
			} else {
				$.ajax({
					type: "POST",
					url: "/set_enable_banner.php",
					data: {
						banneronoff: "0"
							},
					success: function(response){
						console.log(response);
						}
				});
			}
		});
	// Apply event listener to audio toggle
	$("#audio_toggle").change
		(function() {
			if ($(this).is(':checked')) {
				$.ajax({
					type: "POST",
					url: "/set_enable_audio.php",
					data: {
						audioonoff: "1"
						},
					success: function(response){
						console.log(response);
					}
				});
			} else {
				$.ajax({
					type: "POST",
					url: "/set_enable_audio.php",
					data: {
						audioonoff: "0"
							},
					success: function(response){
						console.log(response);
					}
				});
			}
	});
	// Execute initial AJAX Call
	inputsAjax();
}

function getLivestreamStatus(livestreamValue) {
	// this function gets the livestream status from etcd and sets the livestream toggle button on/off upon page load
	$.ajax({
		type: "POST",
		url: "get_livestream_status.php",
		dataType: "json",
		success: function(returned_data) {
		const livestreamValue = JSON.parse(returned_data);
			if (livestreamValue == "1" ) {
				console.log ("Livestream value is 1, enabling toggle automatically.");
				$("#lstoggleinput")[0].checked=true; // set HTML checkbox to checked
				} else {
				console.log ("Livestream value is NOT 1, disabling checkbox toggle.");
				$("#lstoggleinput")[0].checked=false; // set HTML checkbox to unchecked
				}
		}
	})
}

function getBannerStatus(bannerValue) {
	// this function gets the banner status from etcd and sets the banner toggle button on/off upon page load
	$.ajax({
		type: "POST",
		url: "get_banner_status.php",
		dataType: "json",
		success: function(returned_data) {
		const bannerValue = JSON.parse(returned_data);
			if (bannerValue == "1" ) {
				console.log ("Banner value is 1, enabling toggle automatically.");
				$("#banner_toggle_checkbox")[0].checked=true; // set HTML checkbox to checked
				} else {
				console.log ("Banner value is NOT 1, disabling checkbox toggle.");
				$("#banner_toggle_checkbox")[0].checked=false; // set HTML checkbox to unchecked
				}
		}
	})
}

function getAudioStatus(audioValue) {
	// this function gets the audio status from etcd and sets the audio toggle button on/off upon page load
	$.ajax({
		type: "POST",
		url: "get_audio_status.php",
		dataType: "json",
		success: function(returned_data) {
		const audioValue = JSON.parse(returned_data);
			if (audioValue == "1" ) {
				console.log ("Audio value is 1, enabling toggle automatically.");
				$("#audio_toggle_checkbox")[0].checked=true; // set HTML checkbox to checked
				} else {
				console.log ("Audio value is NOT 1, disabling checkbox toggle.");
				$("#audio_toggle_checkbox")[0].checked=false; // set HTML checkbox to unchecked
				}
		}
	})
}

async function getHostIPAJAX(hostName, divEntry) {
	/* Takes the hostname on hover and gets the IP address of the device */
	var queryHostName			=		hostName;
	console.log("Attempting AJAX PHP query for the IP Address of " + queryHostName);
	$.ajax({
			type: "POST",
			url: "/get_host_ip.php",
			data: {
				key: queryHostName,
			},
			success: function(returned_data){
				console.log(returned_data);
				$(divEntry).attr("title", "IP: " + returned_data);
			},
			error: function (xhr, ajaxOption, thrownError) {
			console.log("Failed to get IP Address for hostname", queryHostName);
			throw new Error(thrownerror);
			}
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

function getBlankHostStatus(hostName, hostHash) {
	// this function gets the host blank bit status from etcd, and sets the banner toggle button on/off upon page load
	console.log('Attempting to retrieve host blank bit for: ' + hostName + "," +hostHash);
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
				let matchedElement = 
					// $('#dynamicDecHosts > div > button[data-blankHostName="${blankHostName}"]');
					// $('#btn_blank').find(`[data-hostname="${blankHostName}"]`)
										$('body').find(`[data-blankHostName="${blankHostName}"]`);

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

const callingFunction = (callback) => {
	const callerId = 'calling_function';
	callback(this);
};

function createDeleteButton(hostName, hostHash) {
/* add delete button */
	var $btn				=		$('<button/>', {
		type:   'button',
		text:   'Remove',
		title:  'Delete this host',
		value:  'Remove'+hostHash,      
		class:  'btn renameButton',
		id: 'btn_HostDelete',
		}).click(function(){
			console.log("Deleting host entry and associated keys for: " + hostName + "\nAnd Hash Value:" + hostHash);
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
			})
		})
	return $btn;
}

function createIdentifyButton(hostName, hostHash) {
/* add decoder Identify button */
	var $btn				=		$('<button/>', {
		type:   'button',
		text:   'Identify Host (15s)',
		title:  'Display SMPTE Bars on this host for 15 seconds',
		value:  'Identify'+hostHash,
		class:  'btn identifyButton',
		id: 'btn_identify'
		}).click(function(){
			console.log("Host instructed to reveal itself:" + hostName);
			$(this).addClass('btn_active');
			$.ajax({
				type: "POST",
				url: "/set_reveal_host.php",
				data: {
					key: hostName,
					value: "1"
					},
			success: function(response){
				console.log(response);
			}
		});
	})
return $btn;
}


function createRestartButton(hostName, hostHash) {
/* add task restart button */
	var $btn					=		$('<button/>', {
		type:   'button',
		text:   'Restart Codec Task',
		value:  'Restart'+hostName,
		class:  'btn restartButton',
		title:  'restart codec task',
		id: 'btn_restart'
	}).click(function(){
		console.log("Host instructed to restart UltraGrid task:" + hostName);
		$.ajax({
			type: "POST",
			url: "/set_reset_host.php",
			data: {
				key: hostHash,
				value: "1"
			},
		success: function(response){
			console.log(response);
		}
		});
	})
	return $btn;
}

function createRebootButton(hostName, hostHash) {
/* add reboot button */
	var $btn					=		$('<button/>', {
		type:   'button',
		text:   'Reboot Host',
		class:  'btn rebootButton',
		id: 'btn_reboot',
		title:  'Reboot Host'
		}).click(function(){
			console.log("Host instructed to reboot!" + hostName);
			$.ajax({
				type: "POST",
				url: "/set_reboot_host.php",
				data: {
					key: hostName,
					value: "1"
				},
				success: function(response){
					console.log(response);
				}
			});
		})
	return $btn;
}

function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms || DEF_DELAY));
}

function createBlankButton(hostName, hostHash, thisHostBlankStatus) {
	console.log("Called to create Blank Host button for:" + hostName + ", hash " + hostHash + ", with status" + thisHostBlankStatus);
	var blankHostName			=		hostName;
	var blankHostHash			=		hostHash;
	var thisHostBlankStatus		=		(getBlankHostStatus(hostName, hostHash));
	var blankHostText			=		"pending status";
	var $btn 					= 		$('<button/>', {
		type:           'button',
		text:           blankHostText,
		'data-blankHostName':   blankHostName,
		'data_hover':       'Blank Display',
		data_label:     `${blankHostText}`,
		class:          'btn',
		title:          'Set host to Blank Screen',
		id:         'btn_blank'
		}).click(function(){
			let matchedElement = $('body').find(`[data-blankHostName="${blankHostName}"]`);
			if ($(matchedElement).text() == "Blank Host") {
				console.log("Host instructed to blank screen:" + blankHostName);
				$.ajax({
					type: "POST",
					url: "/set_blank_host.php",
					data: {
						key: blankHostName,
						value: 1
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
					url: "/set_blank_host.php",
					data: {
						key: hostName,
						value: 0
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
/* this is processed through PHP and then handled by the hostname change module, hence it submits hostname and hash data too */
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
		id: 'btn_codec_swap',
		title:  'Change function',
		text:   buttonText
	});
		$btn.click(function(){
			console.log("Host instructed to switch codec functionality:" + hostName);
			$.ajax({
				type: "POST",
				url: "/set_codec_state_change.php",
				data: {
					key: hostName,
					hash: hostHash,
					value: "1"
				},
				success: function(response){
					console.log(response);
				}
			});
		})
	return $btn;
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
	function createDeleteButton() {
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
	$(divEntry).append(createDeleteButton());
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

function createNewHost(key, type, hostName, hostHash, functionIndex) {
	var divEntry					=		document.createElement("Div");
	var type						=		type;
	const id						=		document.createTextNode(counter + 1);
	divEntry.setAttribute("id", id);
	divEntry.setAttribute("divHost", hostHash);
	divEntry.setAttribute("data-fulltext", key);
	divEntry.setAttribute("data-hostName", hostName);
	divEntry.setAttribute("data-hostType", type);
	$(divEntry).addClass('host_divider');
	/* This needs to be done "backwards" insofar as the type needs to be determined before we can start creating a new DIV */
	console.log("Supplied data are---\nKey:" + key + "\nType:" +type + "\nHostname:" + hostName + "\nHash:" + hostHash);

	function createDecoderButtonSet(hostName, hostHash){
	console.log("Generating decoder label and buttons with\nHost Name: " + hostName +"\nAnd Host Hash: " + hostHash + "\nAnd type: " + type + "\nIn Decoders div..\n");
	$(divEntry).append("Host: <input type='text' value="+hostName+" class='hostTextBox'" + " data-hostHash=" + hostHash + " class='input_textbox'>");
		var uiElement = $(".hostTextBox").last();
		uiElement.bind('focus', function() {
			var oldValue 	= $(this).attr("value");	
		});
		uiElement.bind('blur', function() {
			var phpOldValue =   $(this).attr("value");
			var phpHostName =   $(this).val();
			var phpHostHash =   $(this).attr("data-hostHash");
			if ( phpOldValue == phpHostName ) {
				console.log("Error, values have not changed, doing nothing")
			} else {
			confirm('This will reboot the target host!\nProceed?');
			console.log("submitting to set_hostlabel.php with values---\nHash: " + phpHostHash + "\nHostname: " + phpHostName + "\nOld Hostname: " + phpOldValue + "\nType: " + type);
			$.ajax({
				url : '/set_host_label.php',
				type :'post',
				data:{
					hash:       phpHostHash,
					newName:    phpHostName,
					oldName:    phpOldValue,
					type   :    type
					},
				success : function(response) {
					console.log(response);
				}
			});
		}});

	$(divEntry).append(createDeleteButton(hostName, hostHash)); 
	$(divEntry).append(createRestartButton(hostName, hostHash));
	$(divEntry).append(createRebootButton(hostName, hostHash));
	$(divEntry).append(createIdentifyButton(hostName, hostHash));
	var thisHostBlankStatus = (getBlankHostStatus(hostName, hostHash));
	getHostIPAJAX(hostName, divEntry);
	$(divEntry).append(createBlankButton(hostName, hostHash, thisHostBlankStatus));
	$(divEntry).append(createCodecStateChangeButton(hostName, hostHash, type));
	counter ++;
	}
	
	function createEncoderButtonSet(hostName, hostHash){
		console.log("Generating encoder label and buttons with\nHost Name: " + hostName +"\nAnd Host Hash: " + hostHash + "\nAnd type: " + type + "\nIn encoders div..\n");
		$(divEntry).append("Host: <input type='text' value="+hostName+" class='hostTextBox' data-hostHash="+hostHash+" class='input_textbox'>");
		var uiElement = $(".hostTextBox").last();
		uiElement.bind('blur', function() {
			var phpOldValue =   $(this).attr("value");
			var phpHostName =   $(this).val();
			var phpHostHash =   $(this).attr("data-hostHash");
			console.log("submitting to set_hostname.php with values---\nHash: " + phpHostHash + "\nHostname: " + phpHostName + "\nOld Hostname: " + phpOldValue);
			$.ajax({
				url : 'set_host_label.php',
				type :'post',
				data:{
					hash:       phpHostHash,
					newName:    phpHostName,
					oldName:    phpOldValue
				},
				success : function(response) {
					console.log(response);
				}
			});
		});
		$(divEntry).append(createDeleteButton(hostName, hostHash));
		$(divEntry).append(createRestartButton(hostName, hostHash));
		$(divEntry).append(createRebootButton(hostName, hostHash));
		var thisHostBlankStatus = (getBlankHostStatus(hostName, hostHash));
		getHostIPAJAX(hostName, divEntry);
		$(divEntry).append(createBlankButton(hostName, hostHash, thisHostBlankStatus));
		$(divEntry).append(createCodecStateChangeButton(hostName, hostHash, type));
		$(this).addClass('host_divider');
	}
	function createServerButtonSet(hostName, hostHash){
		(divEntry).append("Host:" + hostName);
		console.log("Generating Server label and buttons.");
		$(divEntry).append(createRestartButton(hostName, hostHash));
		$(divEntry).append(createRebootButton(hostName, hostHash));
		getHostIPAJAX(hostName, divEntry);
	}
	function createGatewayButtonSet(hostName, hostHash){
		$(divEntry).append(createDeleteButton(hostName, hostHash));
		$(divEntry).append(createRestartButton(hostName, hostHash));
		$(divEntry).append(createRebootButton(hostName, hostHash));
		$(divEntry).append(createIdentifyButton(hostName, hostHash));
		$(divEntry).append(createBlankButton(hostHash));
	}
	function createLivestreamButtonSet(hostName, hostHash){
		$(divEntry).append(createDeleteButton(hostName, hostHash));
		$(divEntry).append(createRestartButton(hostName, hostHash));
		$(divEntry).append(createRebootButton(hostName, hostHash));
		$(divEntry).append(createIdentifyButton(hostName, hostHash));
		$(divEntry).append(createBlankButton(hostHash));
	}
	switch(type) {
		case 'dec':
			let dynamicdecHosts = document.getElementById('dynamicdecHosts');
			console.log("This is a decoder host");
			console.log("Generating DIV, and calling decoder host generation..\n");
			dynamicdecHosts.appendChild(divEntry);
			createDecoderButtonSet(hostName, hostHash);
			counter++;
			break;
		case 'enc':
			console.log("This is an encoder host");
			dynamicencHosts.appendChild(divEntry);
			createEncoderButtonSet(hostName, hostHash);
			counter++;
			break;
		case 'svr':
			console.log("This is a Server");
			console.log("Generating DIV, and calling server host generation..\n");
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
	//setTimeout(() => window.location.reload(), 750);
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
						console.log("No button with value: " + activeInputHash + " found.");
					}
				});
			},
			error: function (xhr, ajaxOptions, thrownError) {
				console.log(thrownError);
			}
		}).then();
}

$(document).ready(function() {
	getActiveInputHash("your_input_hash");
});