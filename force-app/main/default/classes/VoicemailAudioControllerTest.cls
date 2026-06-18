@isTest
private class VoicemailAudioControllerTest {

    @isTest
    static void returnsLatestAudio() {
        Case c = new Case(Subject = 'Audio test', Origin = 'Phone', Status = 'New');
        insert c;

        ContentVersion cv = new ContentVersion(
            Title = 'Recording',
            PathOnClient = 'recording.wav',
            VersionData = Blob.valueOf('RIFF....WAVE test bytes')
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = c.Id,
            ShareType = 'V'
        );

        Test.startTest();
        ContentVersion result = VoicemailAudioController.getLatestAudio(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected an audio version to be returned');
        System.assertEquals('wav', result.FileExtension, 'Expected the .wav file');
    }

    @isTest
    static void returnsNullWhenNoAudio() {
        Case c = new Case(Subject = 'No audio', Origin = 'Phone', Status = 'New');
        insert c;

        Test.startTest();
        ContentVersion result = VoicemailAudioController.getLatestAudio(c.Id);
        Test.stopTest();

        System.assertEquals(null, result, 'Expected null when no audio is attached');
    }
}
