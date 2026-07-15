Feature: Scan an ID card

  Scenario: Scanning front and back saves a 2-page ID document
    Given the app is launched with a fake ID scanner returning a front and a back
    When I open the ID scanner
    Then an ID card document with 2 pages is saved

  Scenario: Cancelling the back keeps the captured front as a 1-page ID document
    Given the app is launched with a fake ID scanner returning a front then a cancelled back
    When I open the ID scanner
    Then an ID card document with 1 page is saved
