function acqResults = acquisition(longSignal, settings)
//Function performs cold start acquisition on the collected "data". It
//searches for COMPASS signals of all satellites, which are listed in field
//"acqSatelliteList" in the settings structure. Function saves code phase
//and frequency of the detected signals in the "acqResults" structure.
//
//acqResults = acquisition(longSignal, settings)
//
//   Inputs:
//       longSignal    - 11 ms of raw signal from the front-end 
//       settings      - Receiver settings. Provides information about
//                       sampling and intermediate frequencies and other
//                       parameters including the list of the satellites to
//                       be acquired.
//   Outputs:
//       acqResults    - Function saves code phases and frequencies of the 
//                       detected signals in the "acqResults" structure. The
//                       field "carrFreq" is set to 0 if the signal is not
//                       detected for the given PRN number. 
 
//--------------------------------------------------------------------------
//                           SoftGNSS v3.0
// 
// Copyright (C) Darius Plausinaitis and Dennis M. Akos
// Written by Darius Plausinaitis and Dennis M. Akos
// Based on Peter Rinder and Nicolaj Bertelsen
// Updated and converted to scilab 5.3.0 by Artyom Gavrilov
//--------------------------------------------------------------------------
//This program is free software; you can redistribute it and/or
//modify it under the terms of the GNU General Public License
//as published by the Free Software Foundation; either version 2
//of the License, or (at your option) any later version.
//
//This program is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU General Public License for more details.
//
//You should have received a copy of the GNU General Public License
//along with this program; if not, write to the Free Software
//Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
//USA.
//--------------------------------------------------------------------------

// Initialization =========================================================

  // Find number of samples per spreading code
  samplesPerCode = round(settings.samplingFreq / ...
                        (settings.codeFreqBasis / settings.codeLength));

  // Create four 4 msec vectors of data
  // to correlate with (in worst case data loss would not be higher than 1/4):
  signal1 = longSignal(samplesPerCode*0/4+1:4/4*samplesPerCode);
  signal2 = longSignal(samplesPerCode*1/4+1:5/4*samplesPerCode);
  signal3 = longSignal(samplesPerCode*2/4+1:6/4*samplesPerCode);
  signal4 = longSignal(samplesPerCode*3/4+1:7/4*samplesPerCode);
  
  // Find sampling period:
  ts = 1 / settings.samplingFreq;
  
  // Find phase points of the local carrier wave:
  phasePoints = (0 : (samplesPerCode-1)) * 2*%pi*ts;

  // Number of the frequency bins for the given acquisition band 
  numberOfFrqBins = round(settings.acqSearchBand * 2*settings.msCodeLength) + 1;

  // Generate all C/A codes and sample them according to the sampling freq:
  E1BCodesTable = makeE1BCodesTable(settings);
  // Copy vector stCodesTable settings.acqCohIntegration times:
  ///E1BCodesTable = repmat(E1BCodesTable, 1, settings.acqCohIntegration); 
  
  //--- Initialize arrays to speed up the code -------------------------------
  // Search results of all frequency bins and code shifts (for one satellite)
  results     = zeros(numberOfFrqBins, samplesPerCode);
  // Carrier frequencies of the frequency bins
  frqBins     = zeros(1, numberOfFrqBins);
  
//--- Initialize acqResults ------------------------------------------------
  // Carrier frequencies of detected signals
  acqResults.carrFreq     = zeros(1, settings.NumberOfE1BCodes);
  // C/A code phases of detected signals
  acqResults.codePhase    = zeros(1, settings.NumberOfE1BCodes);
  // Correlation peak ratios of the detected signals
  acqResults.peakMetric   = zeros(1, settings.NumberOfE1BCodes);
  
  printf('(');
  
  // Perform search for all listed PRN numbers ...
  for PRN = settings.acqSatelliteList
  
  // Correlate signals ======================================================   
    //--- Perform DFT of C/A code ------------------------------------------
    E1BCodeFreqDom = conj(fft(E1BCodesTable(PRN, :)));

    //--- Make the correlation for whole frequency band (for all freq. bins)
    for frqBinIndex = 1:numberOfFrqBins
      //--- Generate carrier wave frequency grid (freqency step depends
      // on "settings.acqCohIntegration") --------------------------------
      frqBins(frqBinIndex) = settings.IF - ...
                             (settings.acqSearchBand/2) * 1000 + ...
                             (1000 / (2*settings.msCodeLength)) * (frqBinIndex - 1);
      
      //--- Generate local sine and cosine -------------------------------
      sigCarr = exp(%i*frqBins(frqBinIndex) * phasePoints);
      
      //--- "Remove carrier" from the signal and Convert the baseband 
      // signal to frequency domain --------------------------------------
      IQfreqDom1 = fft(sigCarr .* signal1);
      IQfreqDom2 = fft(sigCarr .* signal2);
      IQfreqDom3 = fft(sigCarr .* signal3);
      IQfreqDom4 = fft(sigCarr .* signal4);
      
      //--- Multiplication in the frequency domain (correlation in time domain)
      convCodeIQ1 = IQfreqDom1 .* E1BCodeFreqDom;
      convCodeIQ2 = IQfreqDom2 .* E1BCodeFreqDom;
      convCodeIQ3 = IQfreqDom3 .* E1BCodeFreqDom;
      convCodeIQ4 = IQfreqDom4 .* E1BCodeFreqDom;
      
      //--- Perform inverse DFT and store correlation results ------------
      acqRes1 = abs(ifft(convCodeIQ1)) .^ 2;
      acqRes2 = abs(ifft(convCodeIQ2)) .^ 2;
      acqRes3 = abs(ifft(convCodeIQ3)) .^ 2;
      acqRes4 = abs(ifft(convCodeIQ4)) .^ 2;
      
      //--- Check which 4msec had the greater power and save that, will
      //"blend" 1st and 2nd 4msec but will correct data bit issues
      if     ( (max(acqRes1) > max(acqRes2)) &..
               (max(acqRes1) > max(acqRes3)) &..
               (max(acqRes1) > max(acqRes4)))
        results(frqBinIndex, :) = acqRes1;
        code_phase_corr = 0*samplesPerCode/4;
        code_phase_slot = 1;
      elseif ( (max(acqRes2) > max(acqRes1)) &..
               (max(acqRes2) > max(acqRes3)) &..
               (max(acqRes2) > max(acqRes4)))
        results(frqBinIndex, :) = acqRes2;
        code_phase_corr = 1*samplesPerCode/4;
        code_phase_slot = 12;
      elseif ( (max(acqRes3) > max(acqRes1)) &..
               (max(acqRes3) > max(acqRes2)) &..
               (max(acqRes3) > max(acqRes4)))
        results(frqBinIndex, :) = acqRes3;
        code_phase_corr = 2*samplesPerCode/4;
        code_phase_slot = 3;
      else
        results(frqBinIndex, :) = acqRes4;
        code_phase_corr = 3*samplesPerCode/4;
        code_phase_slot = 4;
      end
    
    end // frqBinIndex = 1:numberOfFrqBins

// Look for correlation peaks in the results ==============================
    // Find the highest peak and compare it to the second highest peak
    // The second peak is chosen not closer than 1 chip to the highest peak
    //pause;
    //--- Find the correlation peak and the carrier frequency --------------
    [peakSize frequencyBinIndex] = max(max(results, 'c'));

    //--- Find code phase of the same correlation peak ---------------------
    [peakSize codePhase] = max(max(results, 'r'));

    //--- Find 1 chip wide CA code phase exclude range around the peak ----
    samplesPerCodeChip   = round(settings.samplingFreq /...
                                 settings.codeFreqBasis);
    excludeRangeIndex1 = codePhase - samplesPerCodeChip;
    excludeRangeIndex2 = codePhase + samplesPerCodeChip;

    //--- Correct C/A code phase exclude range if the range includes array
    //boundaries
    if excludeRangeIndex1 < 2
        codePhaseRange = excludeRangeIndex2 : ...
                         (samplesPerCode + excludeRangeIndex1);
    elseif excludeRangeIndex2 > samplesPerCode
        codePhaseRange = (excludeRangeIndex2 - samplesPerCode) : ...
                         excludeRangeIndex1;
    else
        codePhaseRange = [1:excludeRangeIndex1, ...
                          excludeRangeIndex2 : samplesPerCode];
    end
    
    //--- Find the second highest correlation peak in the same freq. bin ---
    secondPeakSize = max(results(frequencyBinIndex, codePhaseRange));

    //--- Store result -----------------------------------------------------
    acqResults.peakMetric(PRN) = peakSize/secondPeakSize;
    
    // If the result is above threshold, then there is a signal ...
    if (peakSize/secondPeakSize) > settings.acqThreshold
      //--- Indicate PRN number of the detected signal -------------------
      printf('%02d %01d   ', PRN, code_phase_slot);
      acqResults.codePhase(PRN) = codePhase + 16000*2 + 0*code_phase_corr;
      acqResults.carrFreq(PRN)    =...
                               settings.IF - ...
                               (settings.acqSearchBand/2) * 1000 + ...
                               (1000 / (2*settings.msCodeLength)) * (frequencyBinIndex - 1);
        
    else
      //--- No signal with this PRN --------------------------------------
      printf('. ');
    end   // if (peakSize/secondPeakSize) > settings.acqThreshold
    
end    // for PRN = satelliteList

//=== Acquisition is over ==================================================
printf(')\n');

endfunction