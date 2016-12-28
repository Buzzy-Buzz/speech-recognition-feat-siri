/*
    Copyright (C) 2016 - 2017 SOHKAKUDO Ltd. All Rights Reserved.
    See LICENSE.txt for this Plugin’s licensing information
*/
/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    The primary view controller. The speach-to-text engine is managed an configured here.
*/

import UIKit
import Speech

protocol TimeOutDelegate {
    func timeOut(ret: String)
}

protocol OnFinalDelegate {
    func onFinal(ret: String)
}

public class CDVSpeechRecognitionViewController: UIViewController, SFSpeechRecognizerDelegate, SFSpeechRecognitionTaskDelegate {

    // MARK: Properties
    
    /** [API Reference] https://developer.apple.com/reference/speech/sfspeechrecognizer
     The Locale setting is based on setting of iOS. 
     */
    private let speechRecognizer = SFSpeechRecognizer()!
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let audioEngine = AVAudioEngine()


    /** Text returned from speech recognition API */
    private var recognizedText = ""
    
    /** Timer for Speech recognition time limit */
    private var recognitionLimiter: Timer?
    
    /** Speech recognition time limit (maximum time 60 seconds is Apple's limit time) */
    private var recognitionLimitSec: Int = 60
    
    /** Timer for judging the period of silence */
    private var noAudioDurationTimer: Timer?

    /** Threshold for judging period of silence */
    private var noAudioDurationLimitSec: Int = 2

    /** Speech recognition API state */
    private var status: String = ""
    
    internal var delegate: TimeOutDelegate?
    
    internal var onFinalDelegate: OnFinalDelegate?


    required public init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        setup()
    }

    override init(nibName nibNameOrNil: String!, bundle nibBundleOrNil: Bundle!) {
        super.init(nibName: nil, bundle: nil)
        setup()
    }

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    func setup() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            OperationQueue.main.addOperation {
                switch authStatus {
                    case .authorized:
                        self.status = "authorized"
                    case .denied:
                        self.status = "denied"
                    case .restricted:
                        self.status = "restricted"
                    case .notDetermined:
                        self.status = "notDetermined"
                }
            }
        }
    }
    
    /**
     Set Recognition time limitation.
     - parameter v: Specifies the amount of time that the upper limit (in seconds)
     */
    public func setRecognitionLimitSec(v : Int) -> Void {
        self.recognitionLimitSec = v;
    }

    /**
     Plugin Status.
     - return This Plugin's Status: true -> Plugin is Enable, false -> Plugin is Disabled.  
     */
    public func isEnabled() -> Bool {
        return self.status == "authorized"
    }

    private func startRecording() throws {

        // Cancel the previous task if it's running.
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(AVAudioSessionCategoryRecord)
        try audioSession.setMode(AVAudioSessionModeMeasurement)
        try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let inputNode = audioEngine.inputNode else { fatalError("Audio engine has no input node") }
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to created a SFSpeechAudioBufferRecognitionRequest object") }
        
        // Configure request so that results are returned before audio recording is finished
        recognitionRequest.shouldReportPartialResults = true

        // Speech recognition delegate registration
        let recognizer = SFSpeechRecognizer()
        recognizer?.recognitionTask(with: recognitionRequest, delegate: self)

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: SFSpeechRecognizerDelegate
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {}

    // Tells the delegate when the task first detects speech in the source audio.
    // @see https://developer.apple.com/reference/speech/sfspeechrecognitiontaskdelegate/1649206-speechrecognitiondiddetectspeech
    public func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {}

    // Tells the delegate that the task has been canceled.
    // @see https://developer.apple.com/reference/speech/sfspeechrecognitiontaskdelegate/1649200-speechrecognitiontaskwascancelle
    public func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {}

    // Tells the delegate that a hypothesized transcription is available.
    // @see https://developer.apple.com/reference/speech/sfspeechrecognitiontaskdelegate/1649210-speechrecognitiontask
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        self.recognizedText = transcription.formattedString
        // Start judgment of silent time
        self.stopNoAudioDurationTimer()
        self.startNoAudioDurationTimer()
    }

    // Tells the delegate when the task is no longer accepting new audio input, even if final processing is in progress.
    // @see https://developer.apple.com/reference/speech/sfspeechrecognitiontaskdelegate/1649193-speechrecognitiontaskfinishedrea
    public func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {}

    // Tells the delegate when the final utterance is recognized.
    // @see https://developer.apple.com/reference/speech/sfspeechrecognitiontaskdelegate/1649214-speechrecognitiontask
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        self.recognizedText = recognitionResult.bestTranscription.formattedString
    }

    // Tells the delegate when the recognition of all requested utterances is finished.
    // @see https://developer.apple.com/reference/speech/sfspeechrecognitiontaskdelegate/1649215-speechrecognitiontask
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        self.onFinalDelegate?.onFinal(ret: self.recognizedText)
    }

    // MARK: Interface Builder actions
    public func recordButtonTapped() -> String {
        var ret = ""
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            ret = self.recognizedText
            self.stopTimer()
        } else {
            self.recognizedText = ""
            try! startRecording()
            self.startTimer()
            ret = "recognizeNow"
        }
        return ret
    }
    
    func startTimer() {
        recognitionLimiter = Timer.scheduledTimer(
                                timeInterval: TimeInterval(self.recognitionLimitSec),
                                target: self,
                                selector:#selector(InterruptEvent),
                                userInfo: nil,
                                repeats: false
                            )
    }

    func stopTimer() {
        if recognitionLimiter != nil {
            recognitionLimiter?.invalidate()
            recognitionLimiter = nil
        }
    }

    func startNoAudioDurationTimer() {
        noAudioDurationTimer = Timer.scheduledTimer(
                                timeInterval: TimeInterval(self.noAudioDurationLimitSec),
                                target: self,
                                selector:#selector(InterruptEvent),
                                userInfo: nil,
                                repeats: false
                             )
    } 

    func stopNoAudioDurationTimer() {
        if noAudioDurationTimer != nil {
            noAudioDurationTimer?.invalidate()
            noAudioDurationTimer = nil
        }
    }

    func InterruptEvent() {
        var ret = ""
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            ret = self.recognizedText
        }
        guard let inputNode = audioEngine.inputNode else { fatalError("Audio engine has no input node") }
        inputNode.removeTap(onBus: 0)
        self.recognitionRequest = nil
        self.recognitionTask = nil
        recognitionLimiter = nil
        noAudioDurationTimer = nil
        delegate?.timeOut(ret: ret)
    }
}
