/*
	Written by Dmitry Shalkhakov
*/

module dnet.internal.flowinfo;

private import std.date;

/**
	This structs holds data flow information.
*/
private struct FlowInfo {
	const int INFO_SIZE		= 32;	// number of packets info is kept for
	const int INFO_SIZE_MASK	= INFO_SIZE - 1;

	private {
		struct Times {
			long	sent;		// time when the packet has been sent
			long	received;	// time when the packet has been received
		}

		Times[INFO_SIZE]	times;
		int[INFO_SIZE]		latencies;
		int					latency;

		int					bandwidth;	// in bytes per second
		long				packetTime;	// time at which next packet should be sent
	}

	/**
		Sets/gets available downstream bandwidth.
	*/
	public void availableBandwidth( int newBandwidth ) {
		bandwidth = newBandwidth;
	}

	/**
		ditto
	*/
	public int availableBandwidth() {
		return bandwidth;
	}

	/**
		Returns network latency value.
	*/
	public int networkLatency() {
		return latency;
	}

	/**
		Resets the state of the FlowInfo object.
	*/
	public void reset() {
		// reset everything but the bandwidth
		times[] = times.init;
		latencies[] = latencies.init;
		latency = latency.init;
		packetTime = packetTime.init;
	}

	/**
		Called when a packet is sent.
	*/
	public void dataSent( int sequence, int packetSize ) {
		const int HEADER_OVERHEAD	= 48;
		times[sequence & INFO_SIZE_MASK].sent = getUTCtime();

		int msec = ( packetSize + HEADER_OVERHEAD ) * ( 10000 / bandwidth );
		packetTime = getUTCtime() + msec;
	}

	/**
		Called when a packet is received.
	*/
	public void dataReceived( int sequence ) {
		times[sequence & INFO_SIZE_MASK].received = getUTCtime();
		with ( times[sequence & INFO_SIZE_MASK] ) {
			latencies[sequence & INFO_SIZE_MASK] = received - sent;
		}
	}

	/**
		Calculates latency.
	*/
	public void calculateLatency() {
		int	total, count;

		for ( size_t i = 0; i < INFO_SIZE; i++ ) {
			if ( latencies[i] > 0 ) {
				total += latencies[i];
				count++;
			}
		}
		if ( !count ) {
			latency = 0;
		}
		else {
			latency = total / count;
		}
	}

	/**
		Returns true if bandwidth won't be chocked when another packet is sent.
	*/
	public bool readyToTransmit() {
		if ( getUTCtime() > packetTime ) {
			return true;
		}
		return false;
	}
}
