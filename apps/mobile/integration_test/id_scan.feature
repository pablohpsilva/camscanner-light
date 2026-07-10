Feature: Scan an ID card

  Scenario: Accepting front and back saves a 2-page ID document
    Given the app is launched with a fake ID camera returning a front and a back
    When I open the ID scanner
    And I accept the captured front
    And I accept the captured back
    Then an ID card document with 2 pages is saved

  Scenario: Retaking the front then accepting still saves a 2-page ID document
    Given the app is launched with a fake ID camera returning a front and a back
    When I open the ID scanner
    And I retake the front
    And I accept the captured front
    And I accept the captured back
    Then an ID card document with 2 pages is saved
