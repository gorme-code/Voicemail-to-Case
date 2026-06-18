public with sharing class VoicemailAudioController {
    /**
     * Returns the latest audio ContentVersion linked to the given record (e.g. a Case),
     * or null if none is attached. Used by the voicemailAudioPlayer LWC to stream the .wav.
     */
    @AuraEnabled(cacheable=true)
    public static ContentVersion getLatestAudio(Id recordId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ];
        if (links.isEmpty()) {
            return null;
        }
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) {
            docIds.add(l.ContentDocumentId);
        }
        List<ContentVersion> versions = [
            SELECT Id, Title, FileExtension, ContentDocumentId, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
              AND IsLatest = true
              AND FileExtension IN ('wav', 'mp3', 'm4a', 'ogg')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0];
    }
}
