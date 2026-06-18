import { LightningElement, api, wire } from 'lwc';
import getLatestAudio from '@salesforce/apex/VoicemailAudioController.getLatestAudio';

export default class VoicemailAudioPlayer extends LightningElement {
    @api recordId;
    audioUrl;
    fileName;
    hasAudio = false;
    loaded = false;

    @wire(getLatestAudio, { recordId: '$recordId' })
    wiredAudio({ data, error }) {
        this.loaded = true;
        if (data) {
            this.audioUrl = '/sfc/servlet.shepherd/version/download/' + data.Id;
            this.fileName = data.Title + '.' + data.FileExtension;
            this.hasAudio = true;
        } else {
            this.hasAudio = false;
            if (error) {
                // eslint-disable-next-line no-console
                console.error('voicemailAudioPlayer error', error);
            }
        }
    }
}
