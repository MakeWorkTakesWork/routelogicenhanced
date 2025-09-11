@IsTest
private class RouteLogicInputValidatorTest {
    @IsTest static void sanitizeInput_EscapesSingleQuotesOnly() {
        String input = 'O'Hara <b>select drop</b>';
        String out = RouteLogicInputValidator.sanitizeInput(input);
        System.assertEquals('O''Hara <b>select drop</b>', out);
    }
    @IsTest static void sanitizeInput_BlankUnchanged() {
        System.assertEquals(null, RouteLogicInputValidator.sanitizeInput(null));
        System.assertEquals('', RouteLogicInputValidator.sanitizeInput(''));
    }
}
