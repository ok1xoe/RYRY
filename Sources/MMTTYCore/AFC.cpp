// AFC.cpp – doslovný přepis TSound::DoAFC (MMTTY Sound.cpp:479).
// Copyright 2000-2013 Makoto Mori, Nobuyuki Oba; Modifications Copyright 2026 OK1XOE, LGPL v3
// Změny: globály sys.* → AFCParams, fftIN.m_fft → fft, Suspend/Resume vynechány (běží v DSP
// vlákně), CalcBPF() → návratová hodnota AFC_CHANGED_RECALC_BPF, podmínka m_Tx je u volajícího.
#include "AFC.h"
#include <climits>

#define	AFC_PEAKDOWN	128
#define	MARKL	300
#define	SPACEH	2700

static int apply(CFSKDEM& dem, double mfq, double sfq, int bpfafc)
{
	dem.AFCMarkFreq(mfq);
	dem.AFCSpaceFreq(sfq);
	if( bpfafc && (dem.GetAFCMarkFreq() == mfq) && (dem.GetAFCSpaceFreq() == sfq) ){
		return AFC_CHANGED_RECALC_BPF;
	}
	return AFC_CHANGED;
}

int DoAFC(const int* fft, int fftWindow, int bpfafc, CFSKDEM& dem, const AFCParams& p)
{
	double mfq = dem.GetMarkFreq();
	double sfq = dem.GetSpaceFreq();
	double sft = sfq - mfq;
	double sk = sft * 0.5;

	int	nb = (sft < 50.0) ? 1 : 0;
	int xm = mfq * (FFT_SIZE / SampFreq);
	int xs = sfq * (FFT_SIZE / SampFreq);
	int xc = int((xs - xm) * p.sweep);
	int	xe = int(xc * 1.2);
	if( nb ) xe = 80 * (FFT_SIZE / SampFreq);
	int n = 0;
	int avg = 0;

	int x, xx;
	int d;
	int max1H = -INT_MAX;
	int m1H = 0;
	for( x = 0; x < xc; x++ ){		// Mark Peak +
		xx = xm + x;
		if( (xx >= 0) && (xx < fftWindow) ){
			d = fft[xx];
			if( max1H < d ){
				max1H = d;
				m1H = xx;
			}
			else if( (d + AFC_PEAKDOWN) < max1H ){
				break;
			}
		}
	}
	int max1L = -INT_MAX;
	int m1L = 0;
	for( x = 0; x < xe; x++ ){		// Mark Peak -
		xx = xm - x;
		if( (xx >= 0) && (xx < fftWindow) ){
			d = fft[xx];
			avg += d;
			n++;
			if( max1L < d ){
				max1L = d;
				m1L = xx;
			}
			else if( (d + AFC_PEAKDOWN) < max1L ){
				break;
			}
		}
	}
	int max2H = -INT_MAX;
	int m2H = 0;
	for( x = 0; x < xe; x++ ){	// Space Peak +
		xx = xs + x;
		if( (xx >= 0) && (xx < fftWindow) ){
			d = fft[xx];
			avg += d;
			n++;
			if( max2H < d ){
				max2H = d;
				m2H = xx;
			}
			else if( (d + AFC_PEAKDOWN) < max2H ){
				break;
			}
		}
	}
	int max2L = -INT_MAX;
	int m2L = 0;
	for( x = 0; x < xc; x++ ){	// Space Peak -
		xx = xs - x;
		if( (xx >= 0) && (xx < fftWindow) ){
			d = fft[xx];
			if( max2L < d ){
				max2L = d;
				m2L = xx;
			}
			else if( (d + AFC_PEAKDOWN) < max2L ){
				break;
			}
		}
	}
	if( n ) avg /= n;
	if( nb ){
		if( max1L < max1H ){ max1L = max1H; m1L = m1H; }
		if( max1L < max2L ){ max1L = max2L; m1L = m2L; }
		if( max1L < max2H ){ max1L = max2H; m1L = m2H; }
		max2L = max1L;
		m2L = m1L;
	}
	else if( m1H == m2L ){
		if( max2H > max1L ){
			max1L = max1H;
			m1L = m1H;
			max2L = max2H;
			m2L = m2H;
		}
	}
	else {
		if( max1H > max1L ){
			m1L = m1H;
			max1L = max1H;
		}
		if( max2H > max2L ){
			m2L = m2H;
			max2L = max2H;
		}
	}
	if( !nb ){
		switch(p.fftGain){
			case 0:
				if( ((max1L - avg) < p.sq) || ((max2L - avg) < p.sq) ) return 0;
				break;
			case 1:
				if( ((max1L - avg) < p.sq*1.2) || ((max2L - avg) < p.sq*1.2) ) return 0;
				break;
			case 2:
				if( ((max1L - avg) < p.sq*1.5) || ((max2L - avg) < p.sq*1.5) ) return 0;
				break;
			case 3:
				if( ((max1L - avg) < p.sq*1.8) || ((max2L - avg) < p.sq*1.8) ) return 0;
				break;
			default:
				if( ((max1L - avg) < p.sq*0.5) || ((max2L - avg) < p.sq*0.5) ) return 0;
				break;
		}
	}
	else {
		if( (max1L - avg) < p.sq*0.5 ) return 0;
	}
	int ns = m2L - m1L;						// 検出したシフト幅
	if( !nb ){
		if( ns < int(140.0 * (FFT_SIZE / SampFreq)) ) return 0;
	}
	if( ns > int(1500.0 * (FFT_SIZE / SampFreq)) ) return 0;
	int os = (sft * (FFT_SIZE / SampFreq));	// 現在のシフト幅
	double nmfq = m1L * (SampFreq / FFT_SIZE);
	double nsfq = m2L * (SampFreq / FFT_SIZE);
	int ds = ABS(ns-os);					// シフト幅の差
	switch(p.fixShift){
		case 0:		// Free
			if( nb ) goto _fixed;
			if( ((ds <= (os * 1.2)) || nb) && ((nsfq - nmfq) >= 15.0) ){
				if( fabs(nmfq - mfq) >= 2.0 ){
					mfq += (nmfq - mfq)/p.time;
				}
				if( fabs(nsfq - sfq) >= 2.0 ){
					sfq += (nsfq - sfq)/p.time;
				}
				mfq = double(int(mfq+0.5));
				sfq = double(int(sfq+0.5));
				if( mfq < MARKL ) mfq = MARKL;
				if( sfq > SPACEH ) sfq = SPACEH;
				return apply(dem, mfq, sfq, bpfafc);
			}
			break;
		case 1:		// Fixed Shift
_fixed:;
			if( nb ){
				double fq = (nmfq + nsfq) / 2;
				nmfq = fq - sft/2;
				nsfq = fq + sft/2;
			}
			if( ((ds <= (os * 0.25)) || nb) && ((nsfq - nmfq) >= 15.0) ){
				double cfq = (nmfq + nsfq)/2.0;
				nmfq = cfq - sk;
				if( fabs(nmfq - mfq) >= 2.0 ){
					if( nb && (fabs(nmfq - mfq) < 10.0) ){
						mfq += (nmfq - mfq)/(p.time * 4.0);
					}
					else {
						mfq += (nmfq - mfq)/p.time;
					}
					mfq = double(int(mfq+0.5));
					if( mfq < MARKL ) mfq = MARKL;
					if( (mfq + sft) > SPACEH ) mfq = SPACEH - sft;
					sfq = mfq + sft;
					return apply(dem, mfq, sfq, bpfafc);
				}
			}
			break;
		case 2:		// HAM
			if( nb ) goto _fixed;
			if( (ns >= 140.0*FFT_SIZE/SampFreq) && (ns <= 260.0*FFT_SIZE/SampFreq) ){
				sft = nsfq - nmfq;
				if( sft > 230.0 ){
					sft = 240.0;
				}
				else if( sft > 210.0 ){
					sft = 220.0;
				}
				else if( sft > 185 ){
					sft = 200.0;
				}
				else {
					sft = 170.0;
				}
				nsfq = nmfq + sft;
				if( fabs(nmfq - mfq) >= 2.0 ){
					mfq += (nmfq - mfq)/p.time;
				}
				if( fabs(nsfq - sfq) >= 2.0 ){
					sfq += (nsfq - sfq)/p.time;
				}
				mfq = double(int(mfq+0.5));
				sfq = double(int(sfq+0.5));
				if( mfq < MARKL ) mfq = MARKL;
				if( sfq > SPACEH ) sfq = SPACEH;
				return apply(dem, mfq, sfq, bpfafc);
			}
			break;
		case 3:		// FSK
			if( (ns >= 140.0*FFT_SIZE/SampFreq) && (ns <= 260.0*FFT_SIZE/SampFreq) ){
				sft = nsfq - nmfq;
				if( sft > 230.0 ){
					sft = 240.0;
				}
				else if( sft > 210.0 ){
					sft = 220.0;
				}
				else if( sft > 185 ){
					sft = 200.0;
				}
				else {
					sft = 170.0;
				}
				nsfq = nmfq + sft;
				if( fabs(nmfq - mfq) >= 2.0 ){
					nmfq = mfq + (nmfq - mfq)/p.time;
				}
				if( fabs(nsfq - sfq) >= 2.0 ){
					nsfq = sfq + (nsfq - sfq)/p.time;
				}
				sft = nsfq - nmfq;
				if( sft < 175 ) sft = 170;
				if( sft > 195 ) sft = 200;
				sft = double(int((sft*0.5)+0.5));
				nmfq = ((sfq + mfq)*0.5) - sft;
				nsfq = ((sfq + mfq)*0.5) + sft;
				mfq = double(int(nmfq+0.5));
				sfq = double(int(nsfq+0.5));
				if( mfq < MARKL ) mfq = MARKL;
				if( sfq > SPACEH ) sfq = SPACEH;
				return apply(dem, mfq, sfq, bpfafc);
			}
			break;
	}
	return 0;
}
