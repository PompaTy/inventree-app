# VHC mobile integration — step 3

Implemented September 22, 2026.

## Native box browsing

- The navigation menu has a Boxes entry when the server advertises box support and read access.
- The box list searches the server, supports pagination and refresh, and shows status, team color, contents, current location, shipment, and pallet.
- Filters cover status, team, shipment, pallet, current location, and destination. Lost and closed boxes are initially hidden. Selecting either terminal status disables that exclusion. Sorting includes box number in either direction, last update, team, shipment, and location.
- Relationship selectors support server search. Changing shipment clears a previously selected pallet.
- Stock box links and the stock action menu now open the native box detail.
- Box detail has Overview, Contents, and History tabs. Contents preserve decimal quantities and calendar dates/ER/N/A labels, with links to native part and stock pages. Location rows open native location pages.
- History is paginated, newest first, and supports legacy summaries and structured item changes.
- Reads are bound to the account that opened the screen. Responses arriving after an account change are rejected, and disconnect removes displayed box data. Reopen Boxes after changing accounts.
- Empty results, missing boxes, denied access, and failed loads have distinct states. Failed pagination can be retried without discarding existing rows; new searches discard late results from previous searches.

## Scope and validation

Box creation, editing, movement, and scanning workflows remain for later steps. The explicit web action in box detail remains available, using the existing default /web/boxes/<id>/ link.

Thirty targeted tests passed: 15 new browsing tests, 14 step 2 VHC tests, and the existing scanner test. Coverage includes account isolation, pagination, error handling, search, filters, native navigation, audit values, and a 390-pixel phone viewport with enlarged text. Flutter analysis and whitespace checks are also run.

Changes are local and have not been installed on a phone or deployed. Live device/backend acceptance testing remains outstanding. New labels use English fallback until translations are provided.
