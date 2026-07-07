Feature: Platform document scanner

  Scenario: Scanning 2 pages saves a document
    Given the app is launched with a fake scanner returning 2 pages
    When I open the scanner
    And I tap Accept
    Then a document with 2 pages is saved

  Scenario: Cancelling the scanner returns to the home
    Given the app is launched with a fake scanner returning 0 pages
    When I open the scanner
    Then no document is saved
