var script = document.createElement('script');
script.src = 'jquery-3.7.1.min.js';
document.getElementsByTagName('head')[0].appendChild(script);

var dynamicInputs = document.getElementById("dynamicInputs");
dynamicInputs.innerHTML = '';

function firstAjax(){
// get dynamic devices from etcd, and call createNewButton function to generate entries for them.
		$.ajax({
				type: "POST",
				url: "get_inputs.php",
				dataType: "json",
				success: function(returned_data) {
						counter = 3;
						console.log("JSON Inputs data received:");
						console.log(returned_data);
						returned_data.forEach(item => {
										var key = item['key'];
										var value = item['value'];
										var keyFull = item['keyFull'];
										createNewButton(key, value, keyFull);
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
										var key = item['key'];
										var value = item['value'];
										createNewHost(key, value);
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
				$("#bannertoggleinput")[0].checked=true; // set HTML checkbox to checked
				} else {
				console.log ("Banner value is NOT 1, disabling checkbox toggle.");
				$("#bannertoggleinput")[0].checked=false; // set HTML checkbox to unchecked
				}
		}
	})
}

function createNewButton(key, value, keyFull) {
	var divEntry		=	document.createElement("Div");
	var dynamicButton 	= 	document.createElement("Button");
	var renameButton	=	document.createElement("Button");
	const text		=	document.createTextNode(key);
	const id		=	document.createTextNode(counter + 1);
	dynamicButton.id	=	counter;
	/* create a div container, where the button, relabel button and any other associated elements reside */
	dynamicInputs.appendChild(divEntry);
	divEntry.setAttribute("divDeviceHash", value);
	divEntry.setAttribute("data-fulltext", keyFull);
	divEntry.setAttribute("divDevID", dynamicButton.id);
	divEntry.classList.add("dynamicInputButtonDiv");
	console.log("dynamic video source div created for device hash: " + value);
	/* add rename button */
	function createRenameButton() {
		var $btn = $('<button/>', {
				type: 'button',
				text: 'Rename',
				class: 'renameButton clickableButton',
				id: 'btn_rename'
		}).click(relabelInputElement);
	return $btn;
	}
	$(divEntry).append(createRenameButton());
//	divEntry.appendChild(renameButton);
		/* create the button */
		dynamicButton.appendChild(text);
		dynamicButton.setAttribute("value", value);
		dynamicButton.setAttribute("type", "button");
		dynamicButton.setAttribute("data-fulltext", keyFull);
		dynamicButton.classList.add("clickableButton", "dynamicInputButton");
		dynamicButton.addEventListener("click", sendPHPID, setButtonActiveStyle(this, true));
		divEntry.appendChild(dynamicButton);
	/* set counter +1 for button ID */
	counter++;
}

function createNewHost(key, value) {
		var divEntry            =       document.createElement("Div");
		var dynamicButton       =       document.createElement("Button");
		var renameButton        =       document.createElement("Button");
		var deleteButton        =       document.createElement("Button");
		var restartButton       =       document.createElement("Button");
		var rebootButton        =       document.createElement("Button");
		var identifyButton      =       document.createElement("Button");
		const text              =       document.createTextNode(value);
		const id                =       document.createTextNode(counter + 1);
		dynamicButton.id        =       counter;
		/* create a div container, where the button, relabel button and any other associated elements reside */
		dynamicHosts.appendChild(divEntry);
		divEntry.setAttribute("divDeviceHostName", key);
		divEntry.setAttribute("deviceLabel", value);
		divEntry.setAttribute("divDevID", dynamicButton.id);
		divEntry.classList.add("dynamicInputButtonDiv");
		console.log("dynamic Host divider created for device hostname: " + value);
		/* add rename button */
		function createRenameButton() {
				var $btn = $('<button/>', {
								type: 'button',
								text: 'Rename',
								class: 'renameButton clickableButton',
								id: 'btn_rename'
				}).click(relabelHostElement);
		return $btn;
		}
		/* add delete button */
		function createDeleteButton() {
				var $btn = $('<button/>', {
								type: 'button',
								text: 'Remove',
								class: 'renameButton clickableButton',
								id: 'btn_delete'
				}).click(function(){
						$(this).parent().remove();
						console.log("Deleting host entry and all UI elements:" + value);
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
						console.log("Host instructed to reboot:" + key + "," + value);
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
		
		$(divEntry).append(createRenameButton());
		$(divEntry).append(createDeleteButton());	
		$(divEntry).append(createRestartButton());
		$(divEntry).append(createRebootButton());
		$(divEntry).append(createIdentifyButton());
		/* create the button */
		dynamicButton.appendChild(text);
		dynamicButton.setAttribute("value", key);
		dynamicButton.setAttribute("type", "button");
		dynamicButton.classList.add("clickableButton", "dynamicInputButton");
		dynamicButton.addEventListener("click", sendPHPID, setButtonActiveStyle(this, true));
		divEntry.appendChild(dynamicButton);
		/* set counter +1 for button ID */
		counter++;
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
	const selectedDivHash		=	$(this).parent().attr('divDeviceHash');
						console.log("the found hash is: " + selectedDivHash);
	const relabelTarget		=	$(this).parent().attr('divDevID');
						console.log("the found button ID is: " + relabelTarget);
	const oldGenText		=	$(this).parent().attr('data-fulltext');
	const newTextInput		=	prompt("Enter new text label for this device:");
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
				}
				});
	} else {
		return;
	}
}


function relabelHostElement() {
		const selectedDivHost		=		$(this).parent().attr('divDeviceHostName');
											console.log("the found hostname is: " + selectedDivHost);
		const relabelTarget			=       $(this).parent().attr('divDevID');
											console.log("the found button ID is: " + relabelTarget);
		const oldGenText			=       $(this).parent().attr('deviceLabel');
		const newTextInput			=	prompt("Enter new text label for this device:");
		console.log("Device old label is:" + oldGenText);
		console.log("New device label is:" +newTextInput);
		if (newTextInput !== null && newTextInput !== "") {
				document.getElementById(relabelTarget).innerText = newTextInput;
				document.getElementById(relabelTarget).oldGenText = oldGenText;
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