var script = document.createElement('script');
script.src = 'jquery-3.7.1.min.js';
document.getElementsByTagName('head')[0].appendChild(script);

var dynamicInputs = document.getElementById("dynamicInputs");
dynamicInputs.innerHTML = '';

function firstAjax(){
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
										const functionIndex = 1;
										var key = item['key'];
										var value = item['value'];
										var keyFull = item['keyFull'];
										createNewButton(key, value, keyFull, functionIndex);
										})
				},
		complete: function(){
			secondAjax();
		}
		});
}

function secondAjax(){
// get dynamic hosts from etcd, and call createNewHost to generate entries and buttons for them.
	$.ajax({
				type: "POST",
				url: "get_hosts.php",
				dataType: "json",
				success: function(returned_data) {
						counter = 500;
						console.log("JSON Hosts data received:");
						console.log(returned_data);
						returned_data.forEach(item => {
										const functionIndex = 2;
										var key	 = item['key'];
										var value = item['value'];
										createNewHost(key, value);
										})
				},
		complete: function(){
			thirdAjax();
		}
		});
}

function thirdAjax(){
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
										const functionIndex = 3;
										var key = item['key'];
										var value = item['value'];
										var keyFull = item['keyFull'];
										createNewButton(key, value, keyFull, functionIndex);
										})
				},
		});
}

function fetchHostLabelAndUpdateUI(getLabelHostName){
// This function gets hostname | label from etcd and is repsonsible for telling the server which text labels to produce for each host.
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
	var livestreamValue	=	getLivestreamStatus(livestreamValue);
	var bannerValue		=	getBannerStatus(bannerValue);
	/* getLivestreamURLdata(); */
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
	// Execute initial AJAX Call
	firstAjax();
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

function getHostBlankStatus(hostValue) {
	// this function gets the banner status from etcd and sets the banner toggle button on/off upon page load
	console.log('Attempting to retrieve host blank status for: ' + hostValue);
	let retValue = null;

	$.ajax({
		type: "POST",
		url: "get_blank_host_status.php",
		dataType: "json",
		data: {
			key: hostValue
		},
		success: function(returned_data) {
		var retValue = JSON.parse(returned_data);
			if (retValue == 1 ) {
				console.log ("Blank value is:" + retValue)
				} else {
			console.log ("Blank value is:" + retValue);
				}
		},
		error: function() {
		reject(new Error('Error fetching blank status'));  // reject promise if an error occurs
		}
	});
	return retValue;
}

const callingFunction = (callback) => {
	const callerId = 'calling_function';
	callback(this);
};

function createNewButton(key, value, keyFull, functionIndex) {
	var divEntry		=	document.createElement("Div");
	var dynamicButton 	= 	document.createElement("Button");
	const text		=	document.createTextNode(key);
	const id		=	document.createTextNode(counter + 1);
	dynamicButton.id	=	counter;
	/* create a div container, where the button, relabel button and any other associated elements reside */
	if (functionIndex === 1) {
		console.log("called from firstAjax so this is a local video source");
		dynamicInputs.appendChild(divEntry);
	} else if (functionIndex === 3) {
		console.log("called from thirdAjax so this is a network video source");
		dynamicNetworkInputs.appendChild(divEntry);
	} else {
		console.error("createNewButton not called from a valid function");
	}
	//dynamicInputs.appendChild(divEntry);
	divEntry.setAttribute("divDeviceHash", value);
	divEntry.setAttribute("data-fulltext", keyFull);
	divEntry.setAttribute("divDevID", dynamicButton.id);
	divEntry.classList.add("dynamicInputButtonDiv");
	console.log("dynamic video source div created for device hash: " + value + "and label" + key);
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
			console.log("Deleting input entry and associated key:" + key + "and value: " + value);
				$.ajax({
						type: "POST",
						url: "/remove_input.php",
						data: {
								key: key,
								value: value
								},
						success: function(response){
						console.log(response);
						//location.reload(true);
						}
				});
			})
		return $btn;
		}
		$(divEntry).append(createDeleteButton());
		$(divEntry).append(createRenameButton());
		$(divEntry).append(createInputButton(text, value));
	/* set counter +1 for button ID */
	const selectedDivHash			=		$(this).parent().attr('divDeviceHash');
	counter++;
}

function createNewHost(key, value) {
		var divEntry			=		document.createElement("Div");
		var dynamicButton		=		document.createElement("Button");
		var renameButton		=		document.createElement("Button");
		var deleteButton		=		document.createElement("Button");
		var restartButton		=		document.createElement("Button");
		var rebootButton		=		document.createElement("Button");
		var identifyButton		=		document.createElement("Button");
		var checkbox			=		document.createElement("checkbox");
		var labelEntry			=		document.createElement("Div");
		var labelDiv			=		document.createElement("Div");
		var getLabelHostName		=		0;
		const divHostName		=		document.createTextNode(key);
		const id			=		document.createTextNode(counter + 1);
		/* create a div container, where the button, relabel button and any other associated elements reside */
		dynamicHosts.appendChild(divEntry);
		divEntry.setAttribute("divDeviceHostName", key);
		divEntry.setAttribute("deviceLabel", value);
		divEntry.setAttribute("divDevID", value);
		divEntry.classList.add("host_divider");
		console.log("dynamic Host divider created for device hostname: " + key +" with label/value:" + value);
		/* add rename button */
		function createRenameButton() {
				var $btn = $('<button/>', {
								type: 'button',
								text: 'Rename',
								class: 'renameButton clickableButton',
								id: 'btn_rename',
				}).click(relabelHostElement);
		return $btn;
		}
				/* add delete button */
		//      Create a remove button
		function createDeleteButton() {
				var $btn = $('<button/>', {
								type: 'button',
								text: 'Remove',
								class: 'renameButton clickableButton',
								id: 'btn_HostDelete'
				}).click(function(){
					console.log("Deleting host entry and associated keys: " + key + "and hash value: " + value);
					$.ajax({
						type: "POST",
						url: "/remove_host.php",
						data: {
							key: key,
							value: value
							},
						success: function(response){
						console.log(response);
						//location.reload(true);
						//$(this).parent().remove();
						}
					});
				})
			return $btn;
		}
		/* add decoder Identify button */
		function createIdentifyButton() {
				var $btn = $('<button/>', {
								type: 'button',
								text: 'Identify Host (15s)',
								class: 'renameButton clickableButton',
								id: 'btn_identify'
				}).click(function(){
						console.log("Host instructed to reveal itself:" + key + "," + value);
						$.ajax({
								type: "POST",
								url: "/reveal_host.php",
								data: {
										key: key,
										value: "1"
										},
								success: function(response){
								console.log(response);
										}
						});
				})
				return $btn;
		}
		/* add task restart button */
		function createRestartButton() {
				var $btn = $('<button/>', {
								type: 'button',
								text: 'Restart Codec Task',
								class: 'renameButton clickableButton',
								id: 'btn_restart'
				}).click(function(){
						console.log("Host instructed to restart UltraGrid task:" + key + "," + value);
						$.ajax({
								type: "POST",
								url: "/reset_host.php",
								data: {
										key: key,
										value: "1"
										},
								success: function(response){
								console.log(response);
										}
						});

				})
				return $btn;
		}
		/* add decoder reboot button */
		function createRebootButton() {
				var $btn = $('<button/>', {
								type: 'button',
								text: 'Reboot Host',
								class: 'renameButton clickableButton',
								id: 'btn_reboot'
				}).click(function(){
						console.log("Host instructed to reboot:" + key);
						$.ajax({
								type: "POST",
								url: "/reboot_host.php",
								data: {
										key: key,
										value: "1"
										},
								success: function(response){
								console.log(response);
										}
						});

				})
				return $btn;
		}
		/* a subdiv with a text label */
		function createLabelDiv(value){
				var labelEntry                  =               document.createElement("Div");
				var labelText                   =               document.createTextNode(value);
				labelEntry.classList.add("dynamicInputButtonLabelDiv");
				labelEntry.innerHTML = ("Device: " + value);
				labelEntry.id = value;
				labelEntry.style.display = "inline-block";
				labelEntry.style.marginRight = "20px";
				divEntry.appendChild(labelEntry);
				// This event listener monitors for DOM Nodes inserted
				// UNDER $dynamicHosts, and checks for .dynamicCheckBox
				// Effectively it sets the initial status of the blank function
				// on element creation
		}
				/* add a blank button */
				function createBlankButton(key) {
				console.log('setting all hosts OFF blank mode');
				// have to do this because JS seems to be a real mess with AJAX async calls and I couldn't get anything useful out of state detection..
				// wrong tools for the wrong job? 
					console.log("Host instructed to restore display:" + key);
										$.ajax({
												type: "POST",
												url: "/set_blank_host.php",
												data: {
														key: key,
														value: 0
														},
												success: function(response){
												console.log(response);
												}
										});

				console.log('hostname is: ' + key);

				var buttonText = "Blank Screen";
								var $btn = $('<button/>', {
					type: 'button',
										text: buttonText,
										class: 'renameButton clickableButton',
										id: 'btn_blank'
								});
			$btn.click(function(){
				if ($(this).text() == "Blank Screen") {
								console.log("Host instructed to blank screen:" + key);
										$.ajax({
											type: "POST",
												url: "/set_blank_host.php",
												data: {
													key: key,
														value: 1
														},
												success: function(response){
												console.log(response);
												}
										});
						$(this).text('Restore Screen')
					} else {
										console.log("Host instructed to restore display:" + key);
										$.ajax({
											type: "POST",
												url: "/set_blank_host.php",
												data: {
													key: key,
														value: 0
														},
												success: function(response){
												console.log(response);
						}
										});
						$(this).text('Blank Screen')
									}
				});
			console.log("Requested text string is:" + buttonText);
			$btn.text(`${buttonText}`);
					return $btn;
		}
		
		// add button elements
			$(divEntry).append(createLabelDiv(value));
			$(divEntry).append(createRenameButton());
			$(divEntry).append(createDeleteButton());
			$(divEntry).append(createRestartButton());
			$(divEntry).append(createRebootButton());
			$(divEntry).append(createIdentifyButton());
			$(divEntry).append(createBlankButton(key));
}

function sendPHPID(event) {
	postValue = (this.value);
	postLabel = (this.innerText);
		$.ajax({
			type: "POST",
			url: "/hash_select.php",
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
	console.log("Device full label is:" + oldGenText);
	console.log("New input label is:" +newTextInput);
	if (newTextInput !== null && newTextInput !== "") {
		document.getElementById(relabelTarget).innerText = newTextInput;
		document.getElementById(relabelTarget).oldGenText = oldGenText;
		console.log("Button text successfully applied as:" + newTextInput);
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
		const oldGenText			=       $(this).parent().attr('deviceLabel');
		const newTextInput			=		prompt("Enter new text label for this device:");
		console.log("Device old label is:" + oldGenText);
		console.log("New device label is:" +newTextInput);
		if (newTextInput !== null && newTextInput !== "") {
		document.getElementById(targetElement).innerText = newTextInput;
		document.getElementById(targetElement).oldGenText = oldGenText;
		console.log("Button text successfully applied as:" + newTextInput);
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