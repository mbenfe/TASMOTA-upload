/*
 * stm32.cpp
 *
 *  Created on: Mar 17, 2024
 *      Author: benfe
 */
#include <iostream>
#include <string>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <algorithm>
#include <map>
#include "stm32h7xx_hal.h"
#include "main.h"
#include "type.hpp"

using namespace std;

extern "C" void initialiseMapPublish(void);
extern "C" void analyse(string);
extern "C" void sendESP32Data_DMA(uint8_t*, int);
extern "C" void testMemoire(void);
extern "C" vector<string> splitString(string, char);

extern uint32_t getEpoch(void);

void update_statistic(uint8_t, uint8_t, uint8_t);

extern map<int, config_froid> configFroid;
extern map<string, device_registers> danfossControlerRegisters;
extern map<string, device_registers> danfossDeviceRegisters;

extern map<uint8_t, map<uint8_t, etat_statistic>> mapStatistic;

extern uint32_t current_secondes;

extern bool send_statistic_flag;

map<string, float> mapPublish;

vector<string> splitString(string in, char sep) {
	vector<string> r;
	r.reserve(count(in.begin(), in.end(), sep) + 1); // optional
	for (auto p = in.begin();; ++p) {
		auto q = p;
		p = find(p, in.end(), sep);
		r.emplace_back(q, p);
		if (p == in.end())
			return r;
	}
}

string getName(string registre, string type_device) {
	if (registre == "")
		return ("VIDE");
	if (type_device == "device") {
		auto item = danfossDeviceRegisters.find(registre); //device_registers
		if (item != danfossDeviceRegisters.end()) {
			// exists
			return (item->second.name);
		} else
			return (registre);
	} else {
		auto item = danfossControlerRegisters.find(registre);
		if (item != danfossControlerRegisters.end()) {
			// exists
			return (item->second.name);
		} else
			return (registre);
	}
	return (registre);
}

bool isValidHex(const std::string str) {
	if (str.empty())
		return false;
	for (char c : str) {
		if (!isxdigit(c)) {
			return false;
		}
	}
	return true;
}

float getValue(int id, string registre, string value, string type_device) {
	int signe;
	int ivalue;
	if (isValidHex(value))
		ivalue = stoi(value, 0, 16);
	else {
		ivalue = 0;
	}
	if (type_device == "device") {
		auto item = danfossDeviceRegisters.find(registre); //device_registers
		if (item == danfossDeviceRegisters.end()) {
			// doesn't exist
			return (0);
		}
		signe = ivalue & 0x8000;
		signe = signe >> 15;
		if (signe == 1) {
			ivalue ^= 0x7FFF;
			ivalue &= 0x7FFF;
			ivalue *= -1;
			return (ivalue * danfossDeviceRegisters[registre].multiple);
		} else {
			return (ivalue * danfossDeviceRegisters[registre].multiple);
		}
	} else {
		auto item = danfossControlerRegisters.find(registre); //device_registers
		if (item == danfossControlerRegisters.end()) {
			// doesn't exist
			return (0);
		}
		return (ivalue * danfossControlerRegisters[registre].multiple);
	}
	return -999;
}

void publishMqtt(int id, int bus) {
	static char buffer[512] = "";
	static char token[128];
	static int length;

	// doesn't publish 'states' during statistic publishing
	if (send_statistic_flag == true)
		return;
//	HAL_GPIO_WritePin(LED1_GPIO_Port, LED1_Pin, GPIO_PIN_SET);
	sprintf(buffer, "{\"Bus\":%d,\"Name\":\"%s\",\"genre\":\"%s\",", bus, configFroid[id].name.c_str(), configFroid[id].genre.c_str());

	for (auto i : mapPublish) { //mapPublish.end()
		sprintf(token, "\"%s\":%.1f", i.first.c_str(), i.second);
		strcat(token, ",");
		strcat(buffer, token);
	}

	length = strlen(buffer);
	buffer[length - 1] = '}';
	strcat(buffer, "\n");
	length = strlen(buffer);
	sendESP32Data_DMA((uint8_t*) buffer, length);

//	HAL_GPIO_WritePin(LED1_GPIO_Port, LED1_Pin, GPIO_PIN_RESET);
}

bool isValidInteger(const std::string &input) {
	if (input.empty())
		return false;
	size_t start = 0;
	if (input[0] == '+' || input[0] == '-')
		start = 1;
	for (size_t i = start; i < input.length(); i++) {
		if (!std::isdigit(input[i])) {
			return false;
		}
	}
	return true;
}

void update(vector<string> elements) {
	int id;
	int bus;
	unsigned int i;
	bool change = false;

	char debug1[100];
	char debug2[100];
	char debug3[100];
	string name;
	float value = 0.0;
	config_froid block;
	map<string, float> status;
	if (!isValidInteger(elements[0])) {
		return;
	}
	bus = stoi(elements[0]);
	if (!isValidInteger(elements[1]))
		return;
	id = stoi(elements[1]);
	mapPublish = { };
	mapPublish.insert(make_pair("ID", id));
	block = configFroid[id];
	status = configFroid[id].status;
	for (i = 2; i < elements.size(); i += 2) {
		name = getName(elements[i], configFroid[id].type_device);
		strcpy(debug1, elements[i].c_str());
		strcpy(debug2, elements[i + 1].c_str());
		strcpy(debug3, configFroid[id].type_device.c_str());
		value = getValue(id, elements[i], elements[i + 1], configFroid[id].type_device);
		if (status.find(name) != status.end()) {
			// exists
//			if (id == 4 || id == 5 || id == 6 || id == 7 || id == 10 || id == 12 || id == 13) {
//				change = true;
//				configFroid[id].status[name] = value;
//				mapPublish.insert(make_pair(name, value));
//			}
			if (status[name] != value) {
				// new value
				// before update
				if (name == "CtrlState") {
					mapPublish.insert(make_pair("TherAir", status["TherAir"]));
					mapPublish.insert(make_pair("CutoutTemp", status["CutoutTemp"]));
					mapPublish.insert(make_pair("CutinTemp", status["CutinTemp"]));
					update_statistic(id, (uint8_t) status[name], (uint8_t) value);
					// update
					configFroid[id].status[name] = value;
					mapPublish.insert(make_pair(name, value));
					// publish only interesting to app
					change = true;
				}
				// regroupe pour affichage dans l'application
				else if (name == configFroid[id].alias_cutout) {
					mapPublish.insert(make_pair("TherAir", status["TherAir"]));
					mapPublish.insert(make_pair("CtrlState", status["CtrlState"]));
					mapPublish.insert(make_pair("CutinTemp", status["CutinTemp"]));
					// update
					configFroid[id].status["CutoutTemp"] = value;
					mapPublish.insert(make_pair("CutoutTemp", value));
					// publish only interesting to app
					change = true;
				} else if (name == "CutinTemp") {
					mapPublish.insert(make_pair("TherAir", status["TherAir"]));
					mapPublish.insert(make_pair("CtrlState", status["CtrlState"]));
					mapPublish.insert(make_pair("CutoutTemp", status["CutoutTemp"]));
					// update
					configFroid[id].status[name] = value;
					mapPublish.insert(make_pair(name, value));
					// publish only interesting to app
					change = true;
				} else if (name == configFroid[id].alias_sonde) {
					mapPublish.insert(make_pair("CutoutTemp", status["CutoutTemp"]));
					mapPublish.insert(make_pair("CutinTemp", status["CutinTemp"]));
					mapPublish.insert(make_pair("CtrlState", status["CtrlState"]));
					// update
					configFroid[id].status["TherAir"] = value;
					mapPublish.insert(make_pair("TherAir", value));
					// publish only interesting to app
					change = true;
				} else {
					// publish every changes
					mapPublish.insert(make_pair(name, value));
					change = true;
				}
			}
		} else {
			// doesn't exist
			if (name == configFroid[id].alias_cutout) {
				configFroid[id].status.insert(make_pair("CutoutTemp", value));
				mapPublish.insert(make_pair("CutoutTemp", value));
			} else if (name == configFroid[id].alias_sonde) {
				configFroid[id].status.insert(make_pair("TherAir", value));
				mapPublish.insert(make_pair("TherAir", value));
			} else {
				configFroid[id].status.insert(make_pair(name, value));
				mapPublish.insert(make_pair(name, value));
			}
			if (name == "CtrlState") {
				current_secondes = getEpoch();
				mapStatistic[id].insert( { (unsigned char) value, { current_secondes, 0, 0 } });
				mapPublish.insert(make_pair(name, value));
			}
			change = true;
		}
	}
	if (change == true) {
		publishMqtt(id, bus);
	}
}

void analyse(string cppline) {
	vector<string> elements = splitString(cppline, ':');
	update(elements);
}

