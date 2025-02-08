<template>
  <div class="main">
    <div v-for="camera in cameras" :key="camera.id">
      <video :id="'video-' + camera.id" autoplay playsinline muted />
      <audio :id="'audio-' + camera.id" muted />
      <div class="unmute-button" @click="unmuteAudio(camera.id)" v-show="camera.muted">Unmute</div>
      <div class="camera-name">{{ camera.name }}</div>
      <div class="status-text">{{ camera.statusText }}</div>
    </div>
  </div>
</template>

<script>
  const urlParams = new URLSearchParams(window.location.search);
  console.log(urlParams);
  console.log(process.env);
  function getSetting(queryName, envName, defaultValue) {
    return urlParams.get(queryName) || process.env[envName] || defaultValue;
  }

  const HUB_IP = getSetting('hub_ip', 'VUE_APP_HUB_IP');
  const HUB_PORT = getSetting('hub_port', 'VUE_APP_HUB_PORT', '3080');
  const HUB_URL = getSetting('hub_url', 'VUE_APP_HUB_URL', `http://${HUB_IP}:${HUB_PORT}`);
  const HUB_API_KEY = getSetting('hub_api_key', 'VUE_APP_HUB_API_KEY', '');
  const CAMERA_NAME_WHITELIST_REGEX = getSetting('camera_name_whitelist_regex', 'VUE_APP_CAMERA_NAME_WHITELIST_REGEX', '.');

  const axios = require('axios');

  export default {
    data() {
      return {
        cameras: [],
        updateTimer: null
      }
    },
    async mounted() {
      await this.getCameras();
      await this.$nextTick();
      this.startVideoStreams();
    },
    methods: {
      async getCameras() {
        let devices = (await axios.get(this.makeEndpoint('devices'))).data;
        if (devices.status != 'OK') {
          console.log('Couldn\'t retrieve Nest devices.');
          return;
        }

        console.log('Got SDC Nest devices:', devices.devices);
        let cameras = devices.devices.filter(
            device => device.type == 'cam' &&
            device.supportsStreaming &&
            device.name.match(CAMERA_NAME_WHITELIST_REGEX));
        if (cameras.length == 0) {
          console.log('No cameras found.');
          return;
        }

        this.cameras = cameras.map(camera => {
          return {
            id: camera.id,
            name: ((camera.where || '') + ' ' + (camera.name || '')).trim(),
            statusText: 'Connecting ...',
            playing: false,
            muted: true
          };
        });
      },
      startVideoStreams() {
        for (let i = 0; i < this.cameras.length; i++) {
          (async () => {
            let camera = this.cameras[i];

            let remoteVideo = document.getElementById('video-' + camera.id);
            let remoteAudio = document.getElementById('audio-' + camera.id);
            camera.peerConnection = new RTCPeerConnection();

            camera.peerConnection.ontrack = event => {
              console.log('Got WebRTC stream:', event);
              if (event.track.kind == 'video' && remoteVideo.srcObject != event.streams[0]) {
                remoteVideo.srcObject = event.streams[0];
                setTimeout(() => remoteVideo.className = 'video-box', 0);
              } else if (event.track.kind == 'audio' && remoteAudio.srcObject != event.streams[0]) {
                remoteAudio.srcObject = event.streams[0];
              }
              if (!camera.playing) {
                camera.playing = true;
                camera.statusText = 'LIVE';

                setInterval(() => {
                  axios.post(this.makeEndpoint('devices/' + camera.id + '/stream/' + camera.streamId + '/extend'), { }).catch(() => { });
                }, 60000);
              }
            };
            camera.peerConnection.onremovetrack = () => { };
            camera.peerConnection.ondatachannel = () => { };

            try {
              camera.peerConnection.addTransceiver('audio', { direction: 'sendrecv' });
              camera.peerConnection.addTransceiver('video', { direction: 'recvonly' });
              camera.peerConnection.createDataChannel('sendDataChannel', null);
              const offer = await camera.peerConnection.createOffer({ offerToReceiveAudio: 1, offerToReceiveVideo: 1 });
              await camera.peerConnection.setLocalDescription(offer);

              let result = (await axios.post(this.makeEndpoint('devices/' + camera.id + '/stream'), { offer: btoa(offer.sdp) })).data;
              let answer = atob(result.answer);

              await camera.peerConnection.setRemoteDescription({ type: 'answer', sdp: answer });

              camera.streamId = result.streamId;
            } catch(error) {
              console.log(error);
              camera.statusText = 'Error';
            }
          })();
        }
      },
      unmuteAudio(id) {
        document.getElementById('audio-' + id).muted = false;
        document.getElementById('audio-' + id).play();
        this.cameras.find(camera => camera.id == id).muted = false;
      },
      makeEndpoint(endpoint, query) {
        return `${HUB_URL}/api/connect/v1/${endpoint}?key=${HUB_API_KEY}&${query || ''}`;
      }
    }
  }
</script>

<style scoped>
  .main {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(40%, 1fr));
    grid-gap: 1rem;
  }

  .main > div {
    position: relative;
    background: #46a9dd;
    padding: 1rem;
    display: grid;
    place-items: center;
    border-radius: 16px;
    max-width: calc(100vw - 3rem);
  }

  .main > div img {
    width: 100%;
    grid-area: 1/1/2/2;
  }

  .camera-name, .status-text {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .camera-name {
    margin-top: 8px;
    font-weight: 500;
    max-width: 100%;
  }

  .unmute-button {
    position: absolute;
    top: 24px;
    left: 24px;
    width: 80px;
    height: 32px;
    background-color: lightblue;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1px solid darkgray;
    border-radius: 12px;
    cursor: pointer;
  }

  .video-box {
    width: 100%;
    display: flex;
  }
</style>
