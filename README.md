# Shift Manager (WorkApp)

An iOS app (SwiftUI, iOS 16+) for restaurant shift managers and crew.

## What it does

**Managers**
- **Today**: a daily checklist that resets each day and shows who checked each item, reminders with alerts, and important times (for example **Line lock 5:00–7:30 PM: crew can't leave the line**). A red banner shows on every screen while a time block is active, with a notification when it starts and ends.
- **Inventory**: items grouped by category with on-hand vs. par, a "below par" filter, and a shareable order list.
- **Closing**
  - *Set up tasks*: nightly closing tasks by station, plus "tonight only" tasks you can add any time, including after close at 10 PM. Crew see them within about 20 seconds.
  - *Review photos*: every task with its photo status. Open one, look at the photo full screen, then **Approve** or send it back for a **Redo** with a note. You can do this without leaving the office.
- **Notes**: shared to-do notes between managers.
- **More → Appearance**: Theme (System / Light / Dark, default System, which follows the phone) and Colors (Adobo warm-red gradient, the default, or Classic blue). Crew get the same options from the profile menu.

**Crew**
- See tonight's closing tasks, filter to your station, take a photo for each one, and send it to the manager.
- See approvals and redo notes as they come in. On a real device, photos come from the camera only (not the camera roll), so they're taken on the spot.

## Run it

1. On a Mac with Xcode 15 or newer, open `WorkApp.xcodeproj`.
2. Under *Signing & Capabilities*, pick your team (a free Apple ID works for your own iPhone).
3. Plug in your iPhone (with Developer Mode on), pick it as the run destination, and press Run.

(`project.yml` is kept for regenerating the project with XcodeGen once CloudKit is turned on.)

The manager PIN is `1234`. Change `Config.managerPIN` in `WorkApp/App/WorkApp.swift`.

Out of the box it runs in **this-device-only mode** (`Config.useCloudKit = false`), so you can try every screen without any setup.

## Share data across phones (CloudKit)

Crew phones and the manager's phone need a shared backend so photos reach the office. You need a paid Apple Developer account for this.

1. In `project.yml`, uncomment the `entitlements` block. Replace `com.yourcompany` with your own ID in `project.yml` and `Config.cloudKitContainer`. Then run `xcodegen` again.
2. Set `Config.useCloudKit = true`.
3. Run the app once so CloudKit creates the record types. Then go to **CloudKit Console → your container → Schema**:
   - **Indexes**: make `recordName` *Queryable* on every record type. On `ClosingSubmission`, also make `day` and `status` *Queryable*.
   - **Security Roles**: give `_icloud` (Authenticated) **Create / Read / Write** on every record type. By default only a record's creator can edit it, and managers need to edit crew submissions to approve them.
4. Deploy the schema to Production before TestFlight or App Store builds.

Everyone needs to be signed in to iCloud on their device.

## Code layout

```
WorkApp/
  App/WorkApp.swift            entry point, Config, RootView
  Models/Models.swift          all data types + business-day logic (closing runs past midnight)
  Services/Store.swift         DataStore protocol, LocalStore (on-device), CloudKitStore (shared)
  Services/AppState.swift      app state + actions (save, toggle, submit, review)
  Services/Notifier.swift      local notifications for reminders and time blocks
  Views/Shared/                banner, status chip, camera, onboarding
  Views/Manager/               Today, Inventory, Closing, Notes, More
  Views/Crew/                  crew closing list + photo task screen
```

Models are saved as JSON in one CloudKit field, so you can add properties without migrating the schema.

## Known limits / next steps

- The role PIN is checked only on the device. For real use, add proper sign-in.
- The public CloudKit database can be read by anyone who has the app installed. Fine for a pilot. For more privacy, move to a private shared zone or Firebase with auth.
- Get your store's approval before using a personal app for work data and photos.
