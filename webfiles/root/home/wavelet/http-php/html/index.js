var script = document.createElement('script');
script.src = 'jquery-3.7.1.min.js';
document.getElementsByTagName('head')[0].appendChild(script);

var dynamicInputs = document.getElementById("dynamicInputs");
dynamicInputs.innerHTML = '';

function inputsAjax(){
// get dynamic devices from etcd, and call createNewButton function to generate entries for them.
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
				const functionIndex	=	1;
				var key			=	item['key'];
				var value		=	item['value'];
				var keyFull		=	item['keyFull'];
				createNewButton(key, value, keyFull, functionIndex);
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
			counter = 3000;
			console.log("JSON Network Inputs data received:");
			console.log(returned_data);
			returned_data.forEach(item => {
				const functionIndex	=	3;
				var key				=	item['key'];
				var value			=	item['value'];
				var keyFull			=	item['keyFull'];
				createNewButton(key, value, keyFull, functionIndex);
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
				var key  = item['key'];
			})
		}
	});

}

function handlePageLoad() {
	var livestreamValue		=	getLivestreamStatus(livestreamValue);
	var bannerValue			=	getBannerStatus(bannerValue);
	var audioValue			=	getAudioStatus(audioValue);
	var bluetoothMACValue	=	getBluetoothMAC(bluetoothMACValue);
	var audioStatus 		=	getAudioStatus(audioValue);
	var selectedInputHash	=	getActiveInputHash();	
	// Adding classes and attributes to the prepopulated 'static' buttons on the webUI
	const staticInputElements = document.querySelectorAll(".inputStaticButtons");
	staticInputElements.forEach(el => 
		el.addEventListener("click", sendPHPID, setButtonActiveStyle, true));
	// Apply event listener to Livestream toggle
	$("#lstoggleinput").change
		(function() {
			if ($(this).is(':checked')) {
				$.ajax({
					type: "POST",
					url: "/enable_livestream.php",
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
						url: "/enable_livestream.php",
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
							url: "/enable_banner.php",
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
						url: "/enable_banner.php",
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
							url: "/enable_audio.php",
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
						url: "/enable_audio.php",
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

function getActiveInputHash(activeInputHash) {
	// this function retreives the currently active input hash
	$.ajax({
		type: "POST",
		url: "get_uv_hash_select.php",
		dataType: "json",
		success: function(returned_data) {
		const activeInputHash = JSON.parse(returned_data);
		console.log("Selected input hash is:" + activeInputHash);
		}
	})
	return activeInputHash;
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
				var btMACKey            = item['key'];
				var bluetoothMACValue   = item['value'];
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

function createRenameButton(hostName, hostHash) {
	var hostName		=	hostName;
	var hostHash		=	hostHash;
	var renameButtonHash 	=	`Rename${hostHash}`;
	console.log("generating a rename button with unique value: " +renameButtonHash);
/* add rename button */
	var $btn = $('<button/>', {
		type: 'button',
		text: 'Rename',
		value: renameButtonHash,
		class: 'renameButton clickableButton',
		id: 'btn_rename',
	}).click(relabelHostElement);
	return $btn;
}

function createDeleteButton(hostName, hostHash) {
/* add delete button */
	var $btn = $('<button/>', {
		type: 'button',
		text: 'Remove',
				value: 'Remove'+hostHash,		
		class: 'renameButton clickableButton',
		id: 'btn_HostDelete',
		}).click(function(){
			console.log("Deleting host entry and associated key: " + hostName + "\nAnd Hash Value:" + hostHash);
			$.ajax({
				type: "POST",
				url: "/remove_host.php",
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
	var $btn = $('<button/>', {
		type: 'button',
		text: 'Identify Host (15s)',
				value: 'Identify'+hostHash,
		class: 'renameButton clickableButton',
		id: 'btn_identify'
		}).click(function(){
			console.log("Host instructed to reveal itself:" + hostName);
			$(this).addClass('btn_active');
			$.ajax({
				type: "POST",
				url: "/reveal_host.php",
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


function createRestartButton(hostName, hostHash) {
/* add task restart button */
	var $btn = $('<button/>', {
		type: 'button',
		text: 'Restart Codec Task',
				value: 'Restart'+hostHash,
		class: 'renameButton clickableButton',
		id: 'btn_restart'
	}).click(function(){
		console.log("Host instructed to restart UltraGrid task:" + hostName);
		$.ajax({
			type: "POST",
			url: "/reset_host.php",
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
	var $btn = $('<button/>', {
		type: 'button',
		text: 'Reboot Host',
		class: 'renameButton clickableButton',
		id: 'btn_reboot'
		}).click(function(){
			console.log("Host instructed to reboot!" + hostName);
			$.ajax({
				type: "POST",
				url: "/reboot_host.php",
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
	var blankHostName = hostName;
	var blankHostHash = hostHash
	var thisHostBlankStatus = (getBlankHostStatus(hostName, hostHash));
	var blankHostText = "pending status";
/* Add a client blank screen button */
	var $btn = $('<button/>', {
		type: 'button',
		text: blankHostText,
			'data-blankHostName': blankHostName,
		class: 'blankHostButton',
		id: 'btn_blank'
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
	var buttonText = type;
		if (type == "dec"){
			buttonText = 'Enable Encoder';
		} else {
			buttonText = 'Enable Decoder';
		};
	var $btn = $('<button/>', {
		type: 'button',
		class: 'encoderButton clickableButton',
		id: 'btn_codec_swap',
		text: buttonText
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

function createNewButton(key, value, keyFull, functionIndex) {
	var divEntry		=	document.createElement("Div");
	var dynamicButton 	= 	document.createElement("Button");
	const text			=	document.createTextNode(key);
	const id			=	document.createTextNode(counter + 1);
	const title			=	document.createTextNode(key);
	dynamicButton.id	=	counter;
	/* create a div container, where the button, relabel button and any other associated elements reside */
	if (functionIndex === 1) {
		console.log("called from firstAjax, so this is a local video source");
		dynamicInputs.appendChild(divEntry);
	} else if (functionIndex === 3) {
		console.log("called from thirdAjax, so this is a network video source");
		dynamicNetworkInputs.appendChild(divEntry);
		$('#dynamicNetworkInputs').addClass('dynamicNetworkInputs');
	} else {
		console.error("createNewButton not called from a valid function");
	}

	//dynamicInputs.appendChild(divEntry);
	divEntry.setAttribute("divDeviceHash", value);
	divEntry.setAttribute("data-fulltext", keyFull);
	divEntry.setAttribute("divDevID", dynamicButton.id);
	divEntry.classList.add("dynamicInputButtonDiv");
	console.log("dynamic video source div created for device hash: " + value + "and label:  " + key);
	// Create the device button
	function createInputButton(text, value) {
		var $btn = $('<button/>', {
			type: 'button',
			text: key,
			value: value,
			class: 'dynamicInputButton clickableButton',
			id: dynamicButton.id
		}).click(sendPHPID);
		$btn.data("fulltext", keyFull);
		return $btn;
	}
	//	Create a rename button
	function createRenameButton() {
		var $btn = $('<button/>', {
			type: 'button',
			text: 'Rename',
			class: 'renameButton clickableButton',
			id: 'btn_rename'
			}).click(relabelInputElement);
		$btn.data("fulltext", keyFull);
		return $btn;
	}
	//	Create a remove button
	function createDeleteButton() {
		var $btn = $('<button/>', {
			type: 'button',
			text: 'Remove',
			class: 'renameButton clickableButton',
			id: 'btn_delete'
		}).click(function(){
			$(this).parent().remove();
			console.log("Deleting input entry and associated key: " + key + " and value: " + value);
			$.ajax({
				type: "POST",
				url: "/remove_input.php",
				data: {
					key: key,
					value: value
				},
				success: function(response){
					console.log(response);
				}
			});
		})
		return $btn;
	}
	$(divEntry).append(createDeleteButton());
	$(divEntry).append(createRenameButton());
	$(divEntry).append(createInputButton(text, value));
	var createdButton = $(divEntry).find('.dynamicInputButton');
	var currentInput = getActiveInputHash(); 
	if (createdButton.val() == currentInput) {
		console.log("This button is the currently selected input hash, changing CSS to active!");
		$(createdButton.css({
			'background-color': 'red',
			'color': 'white',
			'font-size': '44px'
		}));
	}

	/* set counter +1 for button ID */
	const selectedDivHash			=		$(this).parent().attr('divDeviceHash');
	counter++;
}

function createNewHost(key, type, hostName, hostHash, functionIndex) {
	var divEntry							=				document.createElement("Div");
	var type								=				type;
	const id								=				document.createTextNode(counter + 1);
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
		$(divEntry).append("Host: <input type='text' value="+hostName+" class='hostTextBox' data-hostHash="+hostHash+" class='input_textbox'>");
		var uiElement = $(".hostTextBox").last();
		uiElement.bind('blur', function() {
			var phpOldValue	=	$(this).attr("value");
			var phpHostName	=	$(this).val();
			var phpHostHash	=	$(this).attr("data-hostHash");
			console.log("submitting to set_hostname.php with values---\nHash: " + phpHostHash + "\nHostname: " + phpHostName + "\nOld Hostname: " + phpOldValue);
			$.ajax({
				url : 'set_hostame.php',
				type :'post',
				data:{
					hash:		phpHostHash,
					newName:	phpHostName,
					oldName:	phpOldValue
				},
				success : function(response) {
					console.log(response);
				}
			});
		});
	$(divEntry).append(createDeleteButton(hostName, hostHash)); 
	$(divEntry).append(createRestartButton(hostName, hostHash));
	$(divEntry).append(createRebootButton(hostName, hostHash));
	$(divEntry).append(createIdentifyButton(hostName, hostHash));
	var thisHostBlankStatus = (getBlankHostStatus(hostName, hostHash));
	$(divEntry).append(createBlankButton(hostName, hostHash, thisHostBlankStatus));
	$(divEntry).append(createCodecStateChangeButton(hostName, hostHash, type));
	counter ++;
	}
	function createEncoderButtonSet(hostName, hostHash){
		console.log("Generating encoder label and buttons with\nHost Name: " + hostName +"\nAnd Host Hash: " + hostHash + "\nAnd type: " + type + "\nIn encoders div..\n");
		$(divEntry).append("Host: <input type='text' value="+hostName+" class='hostTextBox' data-hostHash="+hostHash+" class='input_textbox'>");
		var uiElement = $(".hostTextBox").last();
		uiElement.bind('blur', function() {
			var phpOldValue	=	$(this).attr("value");
			var phpHostName	=	$(this).val();
			var phpHostHash	=	$(this).attr("data-hostHash");
			console.log("submitting to set_hostname.php with values---\nHash: " + phpHostHash + "\nHostname: " + phpHostName + "\nOld Hostname: " + phpOldValue);
			$.ajax({
				url : 'set_hostame.php',
				type :'post',
				data:{
					hash:		phpHostHash,
					newName:	phpHostName,
					oldName:	phpOldValue
				},
				success : function(response) {
					console.log(response);
				}
			});
		});
		$(divEntry).append(createRenameButton());
		$(divEntry).append(createDeleteButton());
		$(divEntry).append(createRestartButton());
		$(divEntry).append(createRebootButton());
		$(divEntry).append(createCodecStateChangeButton(hostName, hostHash, type));
		$(this).addClass('host_divider');
	}
	function createServerButtonSet(hostName, hostHash){
		(divEntry).append("Host:" + hostName);
		console.log("Generating Server label and buttons.");
		$(divEntry).append(createRestartButton());
		$(divEntry).append(createRebootButton());
	}
	function createGatewayButtonSet(hostName, hostHash){
		$(divEntry).append(createRenameButton());
		$(divEntry).append(createDeleteButton());
		$(divEntry).append(createRestartButton());
		$(divEntry).append(createRebootButton());
		$(divEntry).append(createIdentifyButton());
		$(divEntry).append(createBlankButton(hostHash));
	}
	function createLivestreamButtonSet(hostName, hostHash){
		$(divEntry).append(createRenameButton());
		$(divEntry).append(createDeleteButton());
		$(divEntry).append(createRestartButton());
		$(divEntry).append(createRebootButton());
		$(divEntry).append(createIdentifyButton());
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
			break;
		case 'svr':
			console.log("This is a Server");
			console.log("Generating DIV, and calling server host generation..\n");
			dynamicsvrHosts.appendChild(divEntry);
			createServerButtonSet(hostName, hostHash);
			break;
	}
}

function sendPHPID(event) {
	postValue = (this.value);
	postLabel = (this.innerText);
	$.ajax({
		type: "POST",
			url: "/set_uv_hash_select.php",
			data: {
				value: postValue,
				label: postLabel
				  },
			success: function(response){
				console.log(response); 
			}
		});
}

function relabelInputElement() {
	const selectedDivHash			=		$(this).parent().attr('divDeviceHash');
											console.log("the found hash is: " + selectedDivHash);
	const relabelTarget				=		$(this).parent().attr('divDevID');
											console.log("the found button ID is: " + relabelTarget);
	const oldGenText				=		$(this).parent().attr('data-fulltext');
	const newTextInput				=		prompt("Enter new text label for this device:");
	console.log("Device full label is: " + oldGenText);
	console.log("New input label is: " +newTextInput);
	if (newTextInput !== null && newTextInput !== "") {
		document.getElementById(relabelTarget).innerText = newTextInput;
		document.getElementById(relabelTarget).oldGenText = oldGenText;
		console.log("Button text successfully applied as: " + newTextInput);
		console.log("The originally generated device field from Wavelet was: " + oldGenText);
		console.log("The button must be activated for any changes to reflect on the video banner!");
		$.ajax({
			type: "POST",
			url: "/set_input_label.php",
			data: {
					value: selectedDivHash,
					label: newTextInput,
					oldvl: oldGenText
				  },
			success: function(response){
				console.log(response);
				location.reload(true);
			}
		});
	} else {
		return;
	}
}

function relabelHostElement(label) {
	var selectedDivHost			=		$(this).parent().attr('divDeviceHostName');
										console.log("the found hostname is: " + selectedDivHost);
	var targetElement			=		$(this).parent().attr('deviceLabel');
										console.log("the associated host label is: " +targetElement);
	var devType					= 		$(this).parent().attr('divHostType');
	const oldGenText			=		$(this).parent().attr('deviceLabel');
	const newTextInput			=		prompt("Enter new text label for this device:");
	console.log("Device old label is: " + oldGenText);
	console.log("New device label is: " +newTextInput);
	if (newTextInput !== null && newTextInput !== "") {
		document.getElementById(targetElement).innerText = newTextInput;
		document.getElementById(targetElement).oldGenText = oldGenText;
		console.log("Button text successfully applied as: " + newTextInput);
		console.log("The originally generated device field from Wavelet was: " + oldGenText);
		$.ajax({
				type: "POST",
				url: "/set_host_label.php",
				data: {
					key: selectedDivHost,
					value: newTextInput,
				},
				success: function(response){
					console.log(response);
					location.reload(true);
					console.log('Task submitted successfully, Wavelet will attempt to change the target hostname and reboot the device now..');
				}
		});
	} else {
		return;
	}
}

function setButtonActiveStyle(button) {
	$(this).removeClass('active');
		$(this).addClass('active');
}

function applyLivestreamSettings() {
	postValue = (this.value);
	var vlsurl = $("#lsurl").val();
	var vapikey = $("#lsapikey").val();
	$.ajax({
		type: "POST",
		url: "/apply_livestream.php",
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
	postValue = (this.value);
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