Feature: iOS Bitcoin donation after tips

  The iOS tip jar additionally shows the display-only Bitcoin section
  (QR + copyable address) after the tip consumables. This is ALWAYS on --
  the old FEATURE_IOS_BTC_DONATION build flag is gone, including for App
  Store builds. The disabled scenario below still covers the hidden state,
  which is now reachable only by an explicit constructor argument or by an
  empty BITCOIN_ADDRESS. Ko-fi stays off on iOS.

  Scenario: iOS shows Bitcoin after tips when enabled
    Given the iOS tip jar with Bitcoin enabled is shown
    Then I see the tip buttons
    And I see the Bitcoin donation section after the tips
    And I do not see the Ko-fi button

  Scenario: iOS hides Bitcoin when disabled
    Given the iOS tip jar with Bitcoin disabled is shown
    Then I see the tip buttons
    And I do not see the Bitcoin donation section
