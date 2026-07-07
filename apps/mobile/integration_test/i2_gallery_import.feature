Feature: I2 Gallery import

  Scenario: Importing a photo from the gallery saves it as a document
    Given the app is launched with camera permission granted and empty storage
    When I import a photo from the gallery
    And I tap Accept
    Then I see a saved document on the home
