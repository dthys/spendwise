const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// Send notification when a new expense is added
exports.sendExpenseNotification = functions.firestore
  .document("expenses/{expenseId}")
  .onCreate(async (snap, context) => {
    try {
      const expense = snap.data();
      const expenseId = context.params.expenseId;

      console.log("📱 New expense created:", expenseId, "by user:",
        expense.paidBy);

      // Get the group information
      const groupDoc = await admin.firestore()
        .collection("groups")
        .doc(expense.groupId)
        .get();

      if (!groupDoc.exists) {
        console.log("❌ Group not found:", expense.groupId);
        return null;
      }

      const group = groupDoc.data();

      // Get the user who paid (to get their name)
      const paidByUserDoc = await admin.firestore()
        .collection("users")
        .doc(expense.paidBy)
        .get();

      const paidByUser = paidByUserDoc.exists ? paidByUserDoc.data() : null;
      const paidByName = paidByUser ? paidByUser.name : "Someone";

      // Get all group members except the one who added the expense
      const memberIds = group.memberIds || [];
      const recipientIds = memberIds.filter((id) => id !== expense.paidBy);

      if (recipientIds.length === 0) {
        console.log("📵 No recipients to notify");
        return null;
      }

      console.log("👥 Recipients:", recipientIds.length);

      // Get user documents for recipients
      const userPromises = recipientIds.map((id) =>
        admin.firestore().collection("users").doc(id).get()
      );
      const userDocs = await Promise.all(userPromises);

      const validTokens = [];

      for (let i = 0; i < userDocs.length; i++) {
        const userDoc = userDocs[i];
        if (userDoc.exists) {
          const userData = userDoc.data();

          // Check if user has FCM token
          if (userData.fcmToken) {
            // Check notification preferences
            const prefs = userData.notificationPreferences || {};
            const expenseNotificationsEnabled = prefs.expenseAdded !== false;

            if (expenseNotificationsEnabled) {
              validTokens.push({
                token: userData.fcmToken,
                userId: recipientIds[i],
                userName: userData.name,
              });
            } else {
              console.log("📵 User", userData.name,
                "has disabled expense notifications");
            }
          } else {
            console.log("❌ No FCM token for user:", userData.name);
          }
        }
      }

      if (validTokens.length === 0) {
        console.log("📵 No valid FCM tokens found");
        return null;
      }

      console.log("✅ Valid tokens:", validTokens.length);

      // Format the amount (use EU format)
      const formattedAmount = `${group.currency} ${expense.amount.toFixed(2)
        .replace(".", ",")}`;

      // Create the notification payload
      const title = `💰 New expense in ${group.name}`;
      const body = `${paidByName} paid ${formattedAmount} for "${
        expense.description}"`;

      // Send notifications to all valid tokens
      const messages = validTokens.map((tokenData) => ({
        token: tokenData.token,
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: "expense_added",
          expenseId: expenseId,
          groupId: expense.groupId,
          groupName: group.name,
          amount: expense.amount.toString(),
          currency: group.currency,
          description: expense.description,
          paidBy: expense.paidBy,
          paidByName: paidByName,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: {
            channelId: "expense_channel",
            priority: "high",
            defaultSound: true,
            defaultVibrateTimings: true,
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: title,
                body: body,
              },
              badge: 1,
              sound: "default",
            },
          },
        },
      }));

      // Send all messages
      const response = await admin.messaging().sendAll(messages);

      console.log("📱 Notifications sent:", response.successCount,
        "success,", response.failureCount, "failed");

      // Clean up invalid tokens
      const tokensToRemove = [];
      response.responses.forEach((result, index) => {
        if (result.error) {
          console.error("❌ Error sending to token:",
            validTokens[index].token, result.error);
          if (result.error.code === "messaging/invalid-registration-token" ||
                result.error.code === "messaging/registration-token-not-registered") {
            tokensToRemove.push({
              userId: validTokens[index].userId,
              token: validTokens[index].token,
            });
          }
        }
      });

      // Remove invalid tokens from user documents
      if (tokensToRemove.length > 0) {
        console.log("🧹 Removing invalid tokens:", tokensToRemove.length);
        const batch = admin.firestore().batch();

        tokensToRemove.forEach((item) => {
          const userRef = admin.firestore().collection("users").doc(item.userId);
          batch.update(userRef, {
            fcmToken: admin.firestore.FieldValue.delete(),
          });
        });

        await batch.commit();
        console.log("✅ Invalid tokens removed");
      }

      return null;
    } catch (error) {
      console.error("❌ Error sending expense notification:", error);
      return null;
    }
  });

// Send notification when an expense is edited
exports.sendExpenseEditNotification = functions.firestore
  .document("expenses/{expenseId}")
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      const expenseId = context.params.expenseId;

      // Check if this is a significant change
      const significantFields = ["description", "amount", "paidBy",
        "splitBetween", "category"];
      const hasSignificantChange = significantFields.some((field) => {
        if (field === "splitBetween") {
          // Compare arrays
          const before = beforeData[field] || [];
          const after = afterData[field] || [];
          return JSON.stringify(before.sort()) !== JSON.stringify(after.sort());
        }
        return beforeData[field] !== afterData[field];
      });

      if (!hasSignificantChange) {
        console.log("📝 No significant changes in expense:", expenseId);
        return null;
      }

      console.log("✏️ Expense edited:", expenseId);

      const expense = afterData;

      // Get group info
      const groupDoc = await admin.firestore()
        .collection("groups")
        .doc(expense.groupId)
        .get();

      if (!groupDoc.exists) {
        return null;
      }

      const group = groupDoc.data();

      // Get editor info
      const editorUserDoc = await admin.firestore()
        .collection("users")
        .doc(expense.paidBy)
        .get();

      const editorUser = editorUserDoc.exists ? editorUserDoc.data() : null;
      const editorName = editorUser ? editorUser.name : "Someone";

      // Get recipients (all members except editor)
      const memberIds = group.memberIds || [];
      const recipientIds = memberIds.filter((id) => id !== expense.paidBy);

      if (recipientIds.length === 0) {
        return null;
      }

      // Get valid tokens for edit notifications
      const userPromises = recipientIds.map((id) =>
        admin.firestore().collection("users").doc(id).get()
      );
      const userDocs = await Promise.all(userPromises);

      const validTokens = [];

      for (let i = 0; i < userDocs.length; i++) {
        const userDoc = userDocs[i];
        if (userDoc.exists) {
          const userData = userDoc.data();

          if (userData.fcmToken) {
            const prefs = userData.notificationPreferences || {};
            const editNotificationsEnabled = prefs.expenseEdited !== false;

            if (editNotificationsEnabled) {
              validTokens.push(userData.fcmToken);
            }
          }
        }
      }

      if (validTokens.length === 0) {
        return null;
      }

      // Create edit notification
      const title = `✏️ Expense updated in ${group.name}`;
      const body = `${editorName} modified "${expense.description}"`;

      const messages = validTokens.map((token) => ({
        token: token,
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: "expense_edited",
          expenseId: expenseId,
          groupId: expense.groupId,
          groupName: group.name,
          description: expense.description,
          editorName: editorName,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: {
            channelId: "expense_channel",
            priority: "high",
          },
        },
      }));

      const response = await admin.messaging().sendAll(messages);
      console.log("📱 Edit notifications sent:", response.successCount,
        "success");

      return null;
    } catch (error) {
      console.error("❌ Error sending expense edit notification:", error);
      return null;
    }
  });

// Send notification when an expense is deleted
exports.sendExpenseDeleteNotification = functions.firestore
  .document("expenses/{expenseId}")
  .onDelete(async (snap, context) => {
    try {
      const expense = snap.data();
      const expenseId = context.params.expenseId;

      console.log("🗑️ Expense deleted:", expenseId);

      const groupDoc = await admin.firestore()
        .collection("groups")
        .doc(expense.groupId)
        .get();

      if (!groupDoc.exists) {
        return null;
      }

      const group = groupDoc.data();
      const memberIds = group.memberIds || [];

      // Get valid tokens
      const userPromises = memberIds.map((id) =>
        admin.firestore().collection("users").doc(id).get()
      );
      const userDocs = await Promise.all(userPromises);

      const validTokens = [];

      for (const userDoc of userDocs) {
        if (userDoc.exists) {
          const userData = userDoc.data();

          if (userData.fcmToken) {
            const prefs = userData.notificationPreferences || {};
            const deleteNotificationsEnabled = prefs.expenseDeleted !== false;

            if (deleteNotificationsEnabled) {
              validTokens.push(userData.fcmToken);
            }
          }
        }
      }

      if (validTokens.length === 0) {
        return null;
      }

      const title = `🗑️ Expense deleted in ${group.name}`;
      const body = `"${expense.description}" was removed from the group`;

      const messages = validTokens.map((token) => ({
        token: token,
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: "expense_deleted",
          groupId: expense.groupId,
          groupName: group.name,
          description: expense.description,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: {
            channelId: "expense_channel",
            priority: "high",
          },
        },
      }));

      const response = await admin.messaging().sendAll(messages);
      console.log("📱 Delete notifications sent:", response.successCount,
        "success");

      return null;
    } catch (error) {
      console.error("❌ Error sending expense delete notification:", error);
      return null;
    }
  });

// Function to test notifications
exports.sendTestNotification = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated",
      "User must be authenticated");
  }

  const userId = context.auth.uid;

  try {
    const userDoc = await admin.firestore().collection("users").doc(userId)
      .get();
    const userData = userDoc.data();

    if (!userData || !userData.fcmToken) {
      throw new functions.https.HttpsError("not-found",
        "User FCM token not found");
    }

    const message = {
      token: userData.fcmToken,
      notification: {
        title: "🧪 Test Notification",
        body: "This is a test notification from Firebase Functions!",
      },
      data: {
        type: "test",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    };

    await admin.messaging().send(message);

    return {success: true, message: "Test notification sent successfully"};
  } catch (error) {
    console.error("❌ Error sending test notification:", error);
    throw new functions.https.HttpsError("internal",
      "Failed to send test notification");
  }
});

// Clean up expired FCM tokens (optional)
exports.cleanupExpiredTokens = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async (context) => {
    console.log("🧹 Starting FCM token cleanup...");

    try {
      // Get all users with FCM tokens
      const usersSnapshot = await admin.firestore()
        .collection("users")
        .where("fcmToken", "!=", null)
        .get();

      console.log(`📱 Found ${usersSnapshot.size} users with FCM tokens`);

      return null;
    } catch (error) {
      console.error("❌ Error during token cleanup:", error);
      return null;
    }
  });