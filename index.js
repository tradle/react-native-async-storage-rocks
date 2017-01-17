
import {
  NativeModules
} from 'react-native'

const AsyncStorage = NativeModules.AsyncRocksDBStorage

export default AsyncStorage

// /**
//  * Sample React Native App
//  * https://github.com/facebook/react-native
//  * @flow
//  */

// import React, { Component } from 'react';
// import {
//   AppRegistry,
//   StyleSheet,
//   Text,
//   View,
//   AsyncStorage
// } from 'react-native';

// // import './test'

// export default class rnasyncstoragerocks extends Component {
//   constructor(props) {
//     super(props)
//     this.state = {
//       data: []
//     }
//   }
//   async componentDidMount() {
//     // await AsyncStorage.clear()

//     let start = Date.now()
//     for (var i = 0; i < 100; i++) {
//       await AsyncStorage.setItem(i + '', i + '')
//       await new Promise(resolve => setTimeout(resolve, 50))
//     }

//     console.log('AsyncStorage setItem x 100', Date.now() - start)

//     start = Date.now()
//     const keys = await AsyncStorage.getAllKeys()
//     console.log('AsyncStorage getAllKeys', Date.now() - start)

//     start = Date.now()
//     const data = await AsyncStorage.multiGet(keys)
//     console.log('AsyncStorage multiGet', Date.now() - start)

//     start = Date.now()
//     await AsyncStorage.multiSet(data)
//     console.log('AsyncStorage multiSet', Date.now() - start)

//     this.setState({ data })
//   }
//   render() {
//     return (
//       <View style={styles.container}>
//         {this.state.data.map(([key, val]) => {
//           return (
//             <Text style={styles.instructions}>
//               {key}: {val}
//             </Text>
//           )
//         })}
//       </View>
//     );
//   }
// }

// const styles = StyleSheet.create({
//   container: {
//     flex: 1,
//     justifyContent: 'center',
//     alignItems: 'center',
//     backgroundColor: '#F5FCFF',
//   },
//   welcome: {
//     fontSize: 20,
//     textAlign: 'center',
//     margin: 10,
//   },
//   instructions: {
//     textAlign: 'center',
//     color: '#333333',
//     marginBottom: 5,
//   },
// });

// AppRegistry.registerComponent('rnasyncstoragerocks', () => rnasyncstoragerocks);
