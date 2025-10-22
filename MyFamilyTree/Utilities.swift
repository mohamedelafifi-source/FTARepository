//
//  Utilities.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//

import AVFoundation
import SwiftUI

var audioPlayer: AVAudioPlayer?

func playErrorSound() {
    
        guard let soundURL = Bundle.main.url(forResource: "error", withExtension: "wav") else {
        print("Error: Sound file not found")
        return
    }

    do {
        audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
        
    } catch {
        print("Error: Could not play sound. \(error.localizedDescription)")
    }
}
////// The other sound i can use is 1106
func ErrorSound()
{
    AudioServicesPlaySystemSound(SystemSoundID(1053))
    //AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    
}

func SuccessSound()
{
    //This is not the correct sound
    AudioServicesPlaySystemSound(SystemSoundID(1005))
    
}


