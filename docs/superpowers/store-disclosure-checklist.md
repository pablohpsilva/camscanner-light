# Store Data-Safety Disclosure Checklist — In-App Feedback Feature

> **These steps are release blockers.** Complete all items in App Store Connect and the Google Play Console before submitting the build that ships in-app feedback. Submitting without updated disclosures violates both stores' policies and may result in rejection or removal.

## Background

The in-app feedback feature (optional, user-initiated) transmits the following data when a user taps *Submit* in the feedback form:

| Data | Notes |
|---|---|
| Feedback message text | Required; user-written |
| Email address | Optional; user-provided |
| App version | Non-personal diagnostic |
| OS version | Non-personal diagnostic |
| Device model | Non-personal diagnostic |
| Language/locale | Non-personal diagnostic |

Data is sent to a Cloudflare Worker, which creates a **publicly visible** GitHub issue. Email addresses, if provided, are publicly visible in the resulting issue. No scanned documents or document contents are ever transmitted.

---

## Apple App Store — App Privacy (Nutrition Labels)

Log in to [App Store Connect](https://appstoreconnect.apple.com) → select the app → *App Privacy*.

### 1. Contact Info → Email Address

- **Collected?** Yes
- **Linked to identity?** Yes — *Linked to the User* (the user provides their own address and it appears publicly in a GitHub issue)
- **Used for tracking?** No
- **Purpose:** App Functionality
- **Optional/required?** User-provided and optional (the form allows submission without an email)

### 2. Diagnostics

- **Collected?** Yes (app version, OS version, device model, language/locale)
- **Linked to identity?** No — *Not Linked to the User*
- **Used for tracking?** No
- **Purpose:** App Functionality

> **Note on device model under "Identifiers":** The App Store Privacy taxonomy distinguishes Diagnostics (crash logs, performance data) from Identifiers (device IDs). App version, OS, model, and locale are generally disclosed under *Diagnostics → Device ID* or *Other Diagnostic Data*. Use whichever Apple category best fits at submission time; the key requirement is that they are declared and marked *not used for tracking*.

### Checklist items

- [ ] Open App Privacy in App Store Connect
- [ ] Add **Contact Info → Email Address**: purpose = App Functionality, linked to user, not for tracking, collection is optional
- [ ] Add **Diagnostics** (or appropriate sub-category): purpose = App Functionality, not linked to user, not for tracking
- [ ] Save and confirm the updated nutrition label preview looks correct before submitting the build

---

## Google Play Console — Data Safety Section

Log in to [Google Play Console](https://play.google.com/console) → select the app → *Policy* → *App content* → *Data safety*.

### Data types to declare

#### Email address (Contact info)

- **Collected?** Yes
- **Shared with third parties?** No (Cloudflare Worker is an infrastructure intermediary, not a third-party data recipient for advertising or analytics purposes; however, the data becomes a public GitHub issue — disclose this in your privacy policy, which is already done)
- **Required or optional?** Optional (user can submit feedback without providing an email)
- **Purpose:** App functionality
- **Encrypted in transit?** Yes (HTTPS to Cloudflare Worker)
- **User can request deletion?** See caveat below

#### App info and performance / Diagnostics (app version, OS version, device model, language)

- **Collected?** Yes
- **Shared with third parties?** No
- **Required or optional?** Collected automatically when feedback is submitted
- **Purpose:** App functionality
- **Encrypted in transit?** Yes
- **User can request deletion?** See caveat below

> **Deletion caveat:** Because submitted feedback becomes a public GitHub issue, "deletion" requires manually closing or editing the GitHub issue. The privacy policy should (and does) note that submitted issues are public. In the Play Console deletion field, select *Yes* and note in your support documentation that users can contact you to request issue removal, but that public GitHub history may retain it.

### Checklist items

- [ ] Open Data safety in Google Play Console
- [ ] Declare **Email address** under *Contact info*: purpose = App functionality, encrypted in transit, not shared for advertising, optional
- [ ] Declare **App diagnostics / App info and performance** data: purpose = App functionality, encrypted in transit, not shared for advertising, collected as part of feedback submission
- [ ] Answer *No* to "Is data shared with third parties?" for advertising purposes (Cloudflare is infrastructure, not an ad partner)
- [ ] Set deletion flag to *Yes* with a note in support docs about the GitHub-issue caveat
- [ ] Save and submit the updated Data safety form

---

## Privacy Policy

The updated privacy policy at `apps/web/privacy.html` already covers all of the above. Ensure the live URL is correctly referenced in both store listings:

- App Store Connect → App Information → Privacy Policy URL
- Google Play Console → Store listing → Privacy policy

---

## Final gate

Do not submit the build that includes in-app feedback until:

1. All Apple App Privacy items above are saved in App Store Connect.
2. All Google Play Data Safety items above are saved and the form is submitted.
3. The live `privacy.html` URL is confirmed reachable and reflects the Feedback section.
