Feature: Password-protect a PDF

  Scenario: Export a password-protected PDF
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I protect with a password
    Then I see the protected PDF confirmation
