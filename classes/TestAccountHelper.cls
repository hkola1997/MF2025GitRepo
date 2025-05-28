@isTest
private class TestAccountHelper {
    @isTest
    static void testCreateAccount() {
        // Call the method
        Account acc = AccountHelper.createAccount('Test Account');

        // Fetch the record from the database
        Account insertedAcc = [SELECT Id, Name FROM Account WHERE Id = :acc.Id];

        // Assert to check if the name matches
        System.assertEquals('Test Account', insertedAcc.Name);
    }
}