import pandas as pd
from scapy.all import rdpcap, IP, TCP, UDP
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

# 1. Parse PCAP and extract raw network features
def extract_raw_features(pcap_path, max_packets=5000):
    packets = rdpcap(pcap_path, count=max_packets)
    feature_list = []
    
    for pkt in packets:
        if IP in pkt:
            features = {
                'len': pkt.len,
                'ttl': pkt.ttl,
                'proto': pkt.proto,
                'sport': pkt.sport if (TCP in pkt or UDP in pkt) else 0,
                'dport': pkt.dport if (TCP in pkt or UDP in pkt) else 0,
                'tcp_flags': int(pkt[TCP].flags) if TCP in pkt else 0,
                'time': float(pkt.time)
            }
            feature_list.append(features)
            
    return pd.DataFrame(feature_list)


df = extract_raw_features('ipv4frags.pcap')

print(df)