Feature: Password-protect a PDF

  Scenario: Export a password-protected PDF
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I protect with a password
    Then I see the protected PDF confirmation
