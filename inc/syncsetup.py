#!/usr/bin/python3
import sys
import xml.dom.minidom
from paramiko import SSHClient
from sshtunnel import SSHTunnelForwarder
from scp import SCPClient
import uuid
import requests
import random, string
import json
import os
import shutil
import pwd, grp
import glob
from pathlib import Path

class G:
	xmlloc = "/root/.config/syncthing/config.xml"
	locations = {
		'target': '/etc/target',
		'ceph': '/etc/ceph',
	}
	syncapiport = 8384
	username = 'root'
	groupname = 'root'


class Syncthing():

	def __init__(self, api_key, host='127.0.0.1', port=8384):
		self.api_key = api_key
		self.host = host
		self.port = port
		self.url = 'http://{}:{}'.format(host, port)
		self.headers = {
			"X-API-Key": api_key
		}
	
	def get_config(self):
		return self._query_get('rest/config', headers=self.headers)
	
	def get_folders(self):
		return self._query_get('rest/config/folders', headers=self.headers)
	
	def get_devices(self):
		return self._query_get('rest/config/devices', headers=self.headers)
		
	def get_devid(self):
		status = self._query_get('rest/system/status', headers=self.headers)
		return status['myID']
	
	def put_folders(self, folders):
		return self._query_put('rest/config/folders', headers=self.headers, data=folders)
	
	def put_devices(self, devices):
		return self._query_put('rest/config/devices', headers=self.headers, data=devices)
	
	def _query_get(self, endpoint, headers=None):
		query_url = "{}/{}".format(self.url, endpoint)
		resp = requests.get(query_url, headers=headers)
		return resp.json()
	
	def _query_put(self, endpoint, headers=None, data=None):
		query_url = "{}/{}".format(self.url, endpoint)
		resp = requests.put(query_url, headers=headers, data=data)
		return resp.text

def getLocalConfig(apikey):
	lapi = Syncthing(apikey)
	lid = lapi.get_devid()
	print("My ID: {}".format(lid))
	lfolders = lapi.get_folders()
	ldevices = lapi.get_devices()
	return (lid, lfolders, ldevices, lapi)

def getRemoteConfig(host, apikey):
	remapiport = G.syncapiport + 1
	tunnel = SSHTunnelForwarder(
		(host, 22),
		ssh_username = 'root',
		ssh_pkey = '/root/.ssh/id_rsa',
		remote_bind_address=('127.0.0.1', G.syncapiport),
		local_bind_address=('127.0.0.1', remapiport)
	)
	tunnel.start()
	rapi = Syncthing(apikey, port=remapiport)
	rid = rapi.get_devid()
	rfolders = rapi.get_folders()
	rdevices = rapi.get_devices()
	return (rid, rfolders, rdevices, rapi)

def getLocalApiKey():
	doc = xml.dom.minidom.parse(G.xmlloc)
	api = doc.getElementsByTagName('apikey')
	for item in api:
		return item.firstChild.nodeValue

def connectSSH(host):
	ssh = SSHClient()
	ssh.load_system_host_keys()
	ssh.connect(host)
	return ssh

def setupFolders(devid, remdevid, folders, devices, remfolders=None):
	uid = pwd.getpwnam(G.username).pw_uid
	gid = grp.getgrnam(G.groupname).gr_gid
	if (not any(d.get('deviceID', 'puppies') == devid for d in devices)):
		print(f"Local device {devid} ({os.uname()[1]})not in configuration, adding")
		devices.append(
			{
				"addresses": [
					"dynamic"
				],
				"allowedNetworks": [],
				"autoAcceptFolders": False,
				"certName": "",
				"compression": "metadata",
				"deviceID": devid,
				"ignoredFolders": [],
				"introducedBy": "",
				"introducer": False,
				"maxRecvKbps": 0,
				"maxRequestKiB": 0,
				"maxSendKbps": 0,
				"name": os.uname()[1],
				"paused": False,
				"remoteGUIPort": 0,
				"skipIntroductionRemovals": False,
				"untrusted": False
			}
		)
	if (not any(d.get('deviceID', 'puppies') == remdevid for d in devices)) and sys.argv[1] != '1':
		print(f"Remote device {devid} not in configuration, adding")
		randid = "{}-{}".format(
				''.join(
					random.choice(
						string.ascii_lowercase + string.digits
					) for _ in range(5)
				),
				''.join(
					random.choice(
						string.ascii_lowercase + string.digits
					) for _ in range(5)
				)
			)
		devices.append(
			{
				"addresses": [
					"dynamic"
				],
				"allowedNetworks": [],
				"autoAcceptFolders": False,
				"certName": "",
				"compression": "metadata",
				"deviceID": remdevid,
				"ignoredFolders": [],
				"introducedBy": "",
				"introducer": False,
				"maxRecvKbps": 0,
				"maxRequestKiB": 0,
				"maxSendKbps": 0,
				"name": randid,
				"paused": False,
				"remoteGUIPort": 0,
				"skipIntroductionRemovals": False,
				"untrusted": False
			}
		)
	
	for key, value in G.locations.items():
		if not os.path.isdir(value):
			os.mkdir(value)
			os.chown(value, uid, gid)
		else:
			if sys.argv[1] != '1':
				shutil.rmtree(value)
				os.mkdir(value)
				os.chown(value, uid, gid)
			for dirpath, dirnames, filenames in os.walk(value):
				os.chown(dirpath, uid, gid)
				for fname in filenames:
					os.chown(os.path.join(dirpath, fname), uid, gid)
		exists = False
		i = 0
		for row in folders:
			if key == row['label'] and value == row['path']:
				print("Match for location {}".format(value))
				exists = True
				break
			i += 1
		
		if exists:
			print(f"Folder {key} exists in configuration, NOT adding")
			if (not any(d.get('deviceID', 'puppies') == remdevid for d in folders[i]['devices'])) and remdevid:
				print(f"Device ID {remdevid} (other server) not found for folder {folders[i]['label']}, adding...")
				folders[i]['devices'].append(
					{
						'deviceID': remdevid,
						'encryptionPassword': '',
						'introducedBy': ''
					},
					
				)
			if (not any(d.get('deviceID', 'puppies') == devid for d in folders[i]['devices'])):
				print(f"Device ID {devid} (this server) not found for folder {folders[i]['label']}, adding...")
				folders[i]['devices'].append(
					{
						'deviceID': devid,
						'encryptionPassword': '',
						'introducedBy': ''
					},
					
				)
		else:
			print(f"Folder {key} not in configuration, adding")
			randid = None
			if remfolders:
				for row in remfolders:
					if row['path'] == value and row['label'] == key:
						print(f"Existing folder found on remote server for `{key}`")
						randid = row['id']
						break
			if not randid:
				randid = "{}-{}".format(
					''.join(
						random.choice(
							string.ascii_lowercase + string.digits
						) for _ in range(5)
					),
					''.join(
						random.choice(
							string.ascii_lowercase + string.digits
						) for _ in range(5)
					)
				)
			folders.append(
				{
					"autoNormalize": True,
					"blockPullOrder": "standard",
					"caseSensitiveFS": False,
					"copiers": 0,
					"copyOwnershipFromParent": False,
					"copyRangeMethod": "standard",
					"devices": [],
					"disableFsync": False,
					"disableSparseFiles": False,
					"disableTempIndexes": False,
					"filesystemType": "basic",
					"fsWatcherDelayS": 10,
					"fsWatcherEnabled": True,
					"hashers": 0,
					"id": randid,
					"ignoreDelete": False,
					"ignorePerms": False,
					"junctionsAsDirs": False,
					"label": key,
					"markerName": ".stfolder",
					"maxConcurrentWrites": 2,
					"maxConflicts": 10,
					"minDiskFree": {
						"unit": "%",
						"value": 1
					},
					"modTimeWindowS": 0,
					"order": "random",
					"path": value,
					"paused": False,
					"pullerMaxPendingKiB": 0,
					"pullerPauseS": 0,
					"rescanIntervalS": 3600,
					"scanProgressIntervalS": 0,
					"type": "sendreceive",
					"versioning": {
						"cleanupIntervalS": 0,
						"fsPath": "",
						"fsType": "basic",
						"params": {},
						"type": ""
					},
					"weakHashThresholdPct": 25
				}
			)
			
			if (not any(d.get('deviceID', 'puppies') == remdevid for d in folders[-1]['devices'])) and remdevid:
				print(f"Device ID {remdevid} (other server) not found in device list, adding...")
				folders[-1]['devices'].append(
					{
						'deviceID': remdevid,
						'encryptionPassword': '',
						'introducedBy': ''
					},
					
				)
			if (not any(d.get('deviceID', 'puppies') == devid for d in folders[-1]['devices'])):
				print(f"Device ID {devid} (this server) not found in device list, adding...")
				folders[-1]['devices'].append(
					{
						'deviceID': devid,
						'encryptionPassword': '',
						'introducedBy': ''
					},
					
				)
	return folders, devices

def getRemoteApiKey(sshconn):
	scpconn = SCPClient(sshconn.get_transport())
	tmpfile = '/tmp/{}.xml'.format(uuid.uuid4())
	scpconn.get(G.xmlloc, tmpfile)
	doc = xml.dom.minidom.parse(tmpfile)
	api = doc.getElementsByTagName('apikey')
	for item in api:
		return item.firstChild.nodeValue



def main():
	# Server number
	try:
		sys.argv[1]
	except:
		print("Server number not provided!")
		return 1
	# first fusion host
	if sys.argv[1] != '1':
		try:
			sys.argv[2]
		except:
			print("First iSCSI host IP address not provided!")
			return 2
	remotekey = None
	remotedevid = None
	remotefolders = None
	remotedevices = None
	localkey = getLocalApiKey()
	localdevid, localfolders, localdevices, localapi = getLocalConfig(localkey)
	if sys.argv[1] != '1':
		print(f"Performing remote server ({sys.argv[2]}) configuration")
		print("--------------------------")
		remotekey = getRemoteApiKey(connectSSH(sys.argv[2]))
		remotedevid, remotefolders, remotedevices, remoteapi = getRemoteConfig(sys.argv[2], remotekey)
		remotefolders, remotedevices = setupFolders(remotedevid, localdevid, remotefolders, remotedevices)
		remoteapi.put_devices(json.dumps(remotedevices))
		remoteapi.put_folders(json.dumps(remotefolders))
	print("")
	print("--------------------------")
	print("Performing local server (127.0.0.1) configuration")
	print("--------------------------")
	localfolders, localdevices = setupFolders(localdevid, remotedevid, localfolders, localdevices, remfolders=remotefolders)
	localapi.put_devices(json.dumps(localdevices))
	localapi.put_folders(json.dumps(localfolders))
	print("--------------------------")
	print("Syncthing configuration complete!")
	return 0

sys.exit(main())
