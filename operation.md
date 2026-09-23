# Operating Wavelet

This is the quick reference. For installation, see the [Documentation section](readme.md#documentation) of the readme.

---

## The 30-second summary

1. Open the "Hamburger" advanced menu on any decoder client entry in the group container.
2. Switch a **decoder** to **UI Mode**.  This will open a browser window to expose the UI controller.  A video feed window should nominally remain visible in the upper right corner of the screen.
3. In the browser window, pick a **source** from the dropdown.
4. Every decoder in that group will display that source sees it on their screen.

That's it. Everything else is optional.

Many of the controls are configured with self-explanatory tooltips, which will appear if the mouse pointer is stationary on that object for a second or two.

---

## Quick start

| Step | What to do |
|------|------------|
| Turn on | Power on the server, then the decoders. |
| Open the control screen | On any decoder, switch it to **UI Mode**. |
| Choose a source | On the control screen, use the **source dropdown** to pick what to show. |
| Show it everywhere | All decoders set to that source display it. |
| Change source | Pick another entry in the dropdown whenever you need to. |

---

## The source dropdown

- **Local inputs** — sources connected to this group.
- **Other chainable inputs** — sources that other groups are currently showing, listed as `group → input`. Pick one to subscribe every device in this group to the active input on that group.

The list refreshes automatically whenever any group changes its source.

---

## Tips

- **Changing source is safe** — it only changes what's actively displayed, it doesn't disconnect anything.
- **UI Mode** is just a way to view/control the system; switching it on doesn't affect what other screens show.
- If a screen looks wrong, change the source away and back again.  If there is still an issue, the device can be reset and we recommend trying that before calling anyone.

---

## "Something's wrong" checklist

Try these in order. Stop when it's fixed.

1. Are the server, infrastructure and the client machines **powered on**?  Is the display powered on?
2. Is it **connected** to the Wavelet Wi-Fi / network?
3. **UI Mode** — is the control screen showing?
4. **Device Status** Do any of the host entries in the UI show a yellow, red or black notification on their health status indicator?  What does the tooltip say when you hover your mount pointer over that indicator?
5. **Source** — is a valid source selected in the dropdown?
6. Change the source away and back again.
7. Reboot the decoder (switch it off, count to five, switch it back on and wait for reboot).

Still stuck? This may be a maintenance task. See **Maintenance** below — or contact whomever installed the system.

---

## Maintenance

Wavelet is an **appliance**: it is designed to run without being updated or patched after installation.

- **Only** connect to the local Wavelet network.
- **Never** plug it into your production/corporate network.
- Maintenance should be done by someone familiar with the system, using a dedicated laptop connected to the Wavelet network (or a monitor and keyboard attached to the server).

If you didn't install the system, ask whomever did.
